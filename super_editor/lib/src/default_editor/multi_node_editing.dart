import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor/src/core/document.dart';
import 'package:super_editor/src/core/document_editor.dart';
import 'package:super_editor/src/core/document_selection.dart';
import 'package:super_editor/src/default_editor/text.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';

final _log = Logger(scope: 'multi_node_editing.dart');

class DeleteSelectionCommand implements EditorCommand {
  DeleteSelectionCommand({
    required this.documentSelection,
  });

  final DocumentSelection documentSelection;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    _log.log('DeleteSelectionCommand', 'DocumentEditor: deleting selection: $documentSelection');
    final nodes = document.getNodesInside(documentSelection.base, documentSelection.extent);

    if (nodes.length == 1) {
      // This is a selection within a single node.
      _deleteSelectionWithinSingleNode(
        document: document,
        documentSelection: documentSelection,
        transaction: transaction,
        node: nodes.first,
      );

      // Done handling single-node selection deletion.
      return;
    }

    final range = document.getRangeBetween(documentSelection.base, documentSelection.extent);

    final startNode = document.getNode(range.start);
    if (startNode == null) {
      throw Exception('Could not locate start node for DeleteSelectionCommand: ${range.start}');
    }
    final startNodePosition = startNode.id == documentSelection.base.nodeId
        ? documentSelection.base.nodePosition
        : documentSelection.extent.nodePosition;

    final endNode = document.getNode(range.end);
    if (endNode == null) {
      throw Exception('Could not locate end node for DeleteSelectionCommand: ${range.end}');
    }
    final endNodePosition = startNode.id == documentSelection.base.nodeId
        ? documentSelection.extent.nodePosition
        : documentSelection.base.nodePosition;

    _deleteNodesBetweenFirstAndLast(
      document: document,
      startNode: startNode,
      endNode: endNode,
      transaction: transaction,
    );

    _log.log('DeleteSelectionCommand', ' - deleting partial selection within the starting node.');
    _deleteSelectionWithinNodeFromPositionToEnd(
      document: document,
      node: startNode,
      nodePosition: startNodePosition,
      transaction: transaction,
    );

    _log.log('DeleteSelectionCommand', ' - deleting partial selection within ending node.');
    _deleteSelectionWithinNodeFromStartToPosition(
      document: document,
      node: endNode,
      nodePosition: endNodePosition,
      transaction: transaction,
    );

    // If the start node and end nodes are both `TextNode`s
    // then we need to consider merging them if one or both are
    // empty.
    if (startNode is! TextNode || endNode is! TextNode) {
      return;
    }

    _log.log('DeleteSelectionCommand', ' - combining last node text with first node text');
    startNode.text = startNode.text.copyAndAppend(endNode.text);

    _log.log('DeleteSelectionCommand', ' - deleting last node');
    transaction.deleteNode(endNode);

    _log.log('DeleteSelectionCommand', ' - done with selection deletion');
  }

  void _deleteSelectionWithinSingleNode({
    required Document document,
    required DocumentSelection documentSelection,
    required DocumentEditorTransaction transaction,
    required DocumentNode node,
  }) {
    _log.log('_deleteSelectionWithinSingleNode', ' - deleting selection withing single node');
    final basePosition = documentSelection.base.nodePosition;
    final extentPosition = documentSelection.extent.nodePosition;

    if (basePosition is BinaryNodePosition) {
      // Binary positions are all-or-nothing. Therefore, partial
      // selection means delete the whole node.
      transaction.deleteNode(node);
    } else if (node is TextNode) {
      _log.log('_deleteSelectionWithinSingleNode', ' - its a TextNode');
      final baseOffset = (basePosition as TextPosition).offset;
      final extentOffset = (extentPosition as TextPosition).offset;
      final startOffset = baseOffset < extentOffset ? baseOffset : extentOffset;
      final endOffset = baseOffset < extentOffset ? extentOffset : baseOffset;
      _log.log('_deleteSelectionWithinSingleNode', ' - deleting from $startOffset to $endOffset');

      node.text = node.text.removeRegion(
        startOffset: startOffset,
        endOffset: endOffset,
      );
    }
  }

  void _deleteNodesBetweenFirstAndLast({
    required Document document,
    required DocumentNode startNode,
    required DocumentNode endNode,
    required DocumentEditorTransaction transaction,
  }) {
    // Delete all nodes between the first node and the last node.
    final startIndex = document.getNodeIndex(startNode);
    final endIndex = document.getNodeIndex(endNode);

    _log.log('_deleteNodesBetweenFirstAndLast', ' - start node index: $startIndex');
    _log.log('_deleteNodesBetweenFirstAndLast', ' - end node index: $endIndex');
    _log.log('_deleteNodesBetweenFirstAndLast', ' - initially ${document.nodes.length} nodes');

    // Remove nodes from last to first so that indices don't get
    // screwed up during removal.
    for (int i = endIndex - 1; i > startIndex; --i) {
      _log.log('_deleteNodesBetweenFirstAndLast', ' - deleting node $i: ${document.getNodeAt(i)?.id}');
      transaction.deleteNodeAt(i);
    }
  }

  void _deleteSelectionWithinNodeFromPositionToEnd({
    required Document document,
    required DocumentNode node,
    required dynamic nodePosition,
    required DocumentEditorTransaction transaction,
  }) {
    if (nodePosition is BinaryNodePosition) {
      _deleteBinaryNode(
        document: document,
        node: node,
        transaction: transaction,
      );
    } else if (nodePosition is TextPosition && node is TextNode) {
      node.text = node.text.removeRegion(
        startOffset: nodePosition.offset,
        endOffset: node.text.text.length,
      );
    } else {
      throw Exception('Unknown node position type: $nodePosition, for node: $node');
    }
  }

  void _deleteSelectionWithinNodeFromStartToPosition({
    required Document document,
    required DocumentNode node,
    required dynamic nodePosition,
    required DocumentEditorTransaction transaction,
  }) {
    if (nodePosition is BinaryNodePosition) {
      _deleteBinaryNode(
        document: document,
        node: node,
        transaction: transaction,
      );
    } else if (nodePosition is TextPosition && node is TextNode) {
      node.text = node.text.removeRegion(
        startOffset: 0,
        endOffset: nodePosition.offset,
      );
    } else {
      throw Exception('Unknown node position type: $nodePosition, for node: $node');
    }
  }

  void _deleteBinaryNode({
    required Document document,
    required DocumentNode node,
    required DocumentEditorTransaction transaction,
  }) {
    // TODO: for now deleting a binary node simply means replacing
    //       it with an empty ParagraphNode because after doing that,
    //       the general deletion logic that called this function will
    //       collapse empty paragraphs together, which gives the
    //       result we want.
    //
    //       We avoid deleting the node because the composer is
    //       depending on the first node still existing at the end of
    //       the deletion. This is a fragile relationship between the
    //       composer and the editor and needs to be addressed.
    _log.log('_deleteBinaryNode', ' - replacing BinaryNode with a ParagraphNode: ${node.id}');

    final newNode = ParagraphNode(id: node.id, text: AttributedText());
    transaction.replaceNode(oldNode: node, newNode: newNode);
  }
}
