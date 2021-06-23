import 'dart:math';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:linkify/linkify.dart';
import 'package:super_editor/src/core/document_editor.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/super_editor.dart';

final _log = Logger(scope: 'common_editor_operations.dart');

/// Performs common, high-level editing and composition tasks
/// with a simplified API.
///
/// [CommonEditorOperations] is intended to provide a simple and
/// easy to use API for common tasks; it is not intended to operate
/// as a fundamental document manipulation tool. [CommonEditorOperations]
/// is built on top of [DocumentEditor], [DocumentLayout], and
/// [DocumentComposer]. Use those core artifacts to implement any
/// operations that are not supported by [CommonEditorOperations].
///
/// For example, compare the following [CommonEditorOperations] calls
/// to their respective implementation:
/// TODO: show 2-3 examples that compare the [CommonEditorOperations]
///       call with the comparable implementation to make it clear
///       that anything this class does, the developer can do directly.
///
/// If you implement operations for your editor that are not provided
/// by [CommonEditorOperations], consider implementing those operations
/// as extension methods on top of [CommonEditorOperations] so that the
/// rest of your editor can use those behaviors as if they were
/// implemented within [CommonEditorOperations].
class CommonEditorOperations {
  CommonEditorOperations({
    required this.editor,
    required this.composer,
    required this.documentLayoutResolver,
  });

  // Marked as protected for extension methods and subclasses
  @protected
  final DocumentEditor editor;
  // Marked as protected for extension methods and subclasses
  @protected
  final DocumentComposer composer;
  // Marked as protected for extension methods and subclasses
  @protected
  final DocumentLayoutResolver documentLayoutResolver;

  /// Clears the [DocumentComposer]'s current selection and sets
  /// the selection to the given collapsed [documentPosition].
  ///
  /// Returns [true] if the selection was set to the given [documentPosition],
  /// or [false] if the given [documentPosition] could not be
  /// resolved to a location within the [Document].
  bool insertCaretAtPosition(DocumentPosition documentPosition) {
    if (editor.document.getNodeById(documentPosition.nodeId) == null) {
      return false;
    }

    composer.selection = DocumentSelection.collapsed(position: documentPosition);
    return true;
  }

  /// Locates the [DocumentPosition] at the given [documentOffset] and
  /// sets the [DocumentComposer]'s selection to that collapsed position.
  ///
  /// If [findNearestPosition] is [true] (the default), then the [DocumentPosition]
  /// nearest the given [documentOffset] is used. If [findNearestPosition] is
  /// [false] then the selection is only changed if the given [documentOffset]
  /// sits directly on top of a valid [DocumentPosition], e.g., within the
  /// bounding box of a line of text, or within the bounds of an image.
  ///
  /// Returns [true] if the selection is set based on the given [documentOffset],
  /// or [false] if no relevant [DocumentPosition could be located.
  bool insertCaretAtOffset(
    Offset documentOffset, {
    findNearestPosition = true,
  }) {
    DocumentPosition? position;
    if (findNearestPosition) {
      position = documentLayoutResolver().getDocumentPositionNearestToOffset(documentOffset);
    } else {
      position = documentLayoutResolver().getDocumentPositionAtOffset(documentOffset);
    }

    if (position != null) {
      composer.selection = DocumentSelection.collapsed(position: position);
      return true;
    } else {
      return false;
    }
  }

  /// Sets the [DocumentComposer]'s selection to a [DocumentSelection]
  /// that spans from [baseDocumentPosition] to [extentDocumentPosition]
  /// with the selection direction going from the base position to the
  /// extent position.
  ///
  /// Returns [true] if the selection is successfully changed. Returns
  /// [false] if either [DocumentPosition] could not be mapped to locations
  /// within the [Document], and therefore the selection could not be set.
  bool selectRegion({
    required DocumentPosition baseDocumentPosition,
    required DocumentPosition extentDocumentPosition,
  }) {
    if (editor.document.getNodeById(baseDocumentPosition.nodeId) == null) {
      return false;
    }
    if (editor.document.getNodeById(extentDocumentPosition.nodeId) == null) {
      return false;
    }

    composer.selection = DocumentSelection(
      base: baseDocumentPosition,
      extent: extentDocumentPosition,
    );

    return true;
  }

  /// Given a collapsed selection in a [TextNode], expands the
  /// [DocumentComposer]'s selection to include the entire word in
  /// which the current selection sits.
  ///
  /// Returns [true] if a word was selected. Returns [false] if no
  /// selection could be computed, e.g., the selection was not collapsed,
  /// the selection was not in a [TextNode].
  bool selectSurroundingWord() {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.nodeId != composer.selection!.extent.nodeId) {
      return false;
    }

    final selectedNode = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (selectedNode is! TextNode) {
      return false;
    }

    final docSelection = composer.selection!;
    final currentSelection = TextSelection(
      baseOffset: (docSelection.base.nodePosition as TextNodePosition).offset,
      extentOffset: (docSelection.extent.nodePosition as TextNodePosition).offset,
    );
    final selectedText = currentSelection.textInside(selectedNode.text.text);

    if (selectedText.contains(' ')) {
      // The selection already spans multiple paragraphs. Nothing to do.
      return false;
    }

    final wordTextSelection = expandPositionToWord(
      text: selectedNode.text.text,
      textPosition: TextPosition(offset: (docSelection.extent.nodePosition as TextNodePosition).offset),
    );
    final wordNodeSelection = TextNodeSelection.fromTextSelection(wordTextSelection);

    composer.selection = DocumentSelection(
      base: DocumentPosition(
        nodeId: selectedNode.id,
        nodePosition: wordNodeSelection.base,
      ),
      extent: DocumentPosition(
        nodeId: selectedNode.id,
        nodePosition: wordNodeSelection.extent,
      ),
    );

    return true;
  }

  /// Given a selection in a [TextNode], expands the [DocumentComposer]'s
  /// selection to include the entire paragraph in which the current
  /// selection sits.
  ///
  /// Returns [true] if a paragraph was selected. Returns [false] if no
  /// selection could be computed, e.g., the existing selection spanned
  /// more than one paragraph, the selection spanned multiple nodes,
  /// the selection was not in a [TextNode].
  bool selectSurroundingParagraph() {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.nodeId != composer.selection!.extent.nodeId) {
      return false;
    }

    final selectedNode = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (selectedNode is! TextNode) {
      return false;
    }

    final docSelection = composer.selection!;
    final currentSelection = TextSelection(
      baseOffset: (docSelection.base.nodePosition as TextNodePosition).offset,
      extentOffset: (docSelection.extent.nodePosition as TextNodePosition).offset,
    );
    final selectedText = currentSelection.textInside(selectedNode.text.text);

    if (selectedText.contains('\n')) {
      // The selection already spans multiple paragraphs. Nothing to do.
      return false;
    }

    final paragraphTextSelection = expandPositionToParagraph(
      text: selectedNode.text.text,
      textPosition: TextPosition(offset: (docSelection.extent.nodePosition as TextNodePosition).offset),
    );
    final paragraphNodeSelection = TextNodeSelection.fromTextSelection(paragraphTextSelection);

    composer.selection = DocumentSelection(
      base: DocumentPosition(
        nodeId: selectedNode.id,
        nodePosition: paragraphNodeSelection.base,
      ),
      extent: DocumentPosition(
        nodeId: selectedNode.id,
        nodePosition: paragraphNodeSelection.extent,
      ),
    );

    return true;
  }

  /// Sets the [DocumentComposer]'s selection to include the entire
  /// [Document].
  ///
  /// Always returns [true].
  bool selectAll() {
    final nodes = editor.document.nodes;
    if (nodes.isEmpty) {
      return false;
    }

    composer.selection = DocumentSelection(
      base: DocumentPosition(
        nodeId: nodes.first.id,
        nodePosition: nodes.first.beginningPosition,
      ),
      extent: DocumentPosition(
        nodeId: nodes.last.id,
        nodePosition: nodes.last.endPosition,
      ),
    );

    return true;
  }

  /// Collapses the [DocumentComposer]'s selection at the current
  /// extent [DocumentPosition].
  ///
  /// Returns [true] if the selection was collapsed, or [false] if
  /// there was no selection to collapse.
  bool collapseSelection() {
    if (composer.selection == null) {
      return false;
    }

    composer.selection = composer.selection!.collapse();

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent position in the
  /// upstream direction (to the left for left-to-right languages).
  ///
  /// Expands/contracts the selection if [expand] is [true], otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// By default, moves one character at a time when the extent sits in
  /// a [TextNode]. To move word-by-word, pass [MovementModifier.word]
  /// in [movementModifiers]. To move to the beginning of a line, pass
  /// [MovementModifier.line] in [movementModifiers].
  ///
  /// Returns [true] if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// [false] if the extent did not move and the selection did not change.
  bool moveCaretUpstream({
    bool expand = false,
    Set<MovementModifier> movementModifiers = const {},
  }) {
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed && !expand) {
      composer.selection = composer.selection!.collapseUpstream(editor.document);
      return true;
    }

    final currentExtent = composer.selection!.extent;
    final nodeId = currentExtent.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    final extentComponent = documentLayoutResolver().getComponentByNodeId(nodeId);
    if (extentComponent == null) {
      return false;
    }

    String newExtentNodeId = nodeId;
    dynamic newExtentNodePosition = extentComponent.movePositionLeft(currentExtent.nodePosition, movementModifiers);

    if (newExtentNodePosition == null) {
      // Move to next node
      final nextNode = editor.document.getNodeBefore(node);

      if (nextNode == null) {
        // We're at the beginning of the document and can't go anywhere.
        return false;
      }

      newExtentNodeId = nextNode.id;
      final nextComponent = documentLayoutResolver().getComponentByNodeId(nextNode.id);
      if (nextComponent == null) {
        return false;
      }
      newExtentNodePosition = nextComponent.getEndPosition();
    }

    final newExtent = DocumentPosition(
      nodeId: newExtentNodeId,
      nodePosition: newExtentNodePosition,
    );

    if (expand) {
      // Selection should be expanded.
      composer.selection = composer.selection!.expandTo(
        newExtent,
      );
    } else {
      // Selection should be replaced by new collapsed position.
      composer.selection = DocumentSelection.collapsed(
        position: newExtent,
      );
    }

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent position in the
  /// downstream direction (to the right for left-to-right languages).
  ///
  /// Expands/contracts the selection if [expand] is [true], otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// By default, moves one character at a time when the extent sits in
  /// a [TextNode]. To move word-by-word, pass [MovementModifier.word]
  /// in [movementModifiers]. To move to the end of a line, pass
  /// [MovementModifier.line] in [movementModifiers].
  ///
  /// Returns [true] if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// [false] if the extent did not move and the selection did not change.
  bool moveCaretDownstream({
    bool expand = false,
    Set<MovementModifier> movementModifiers = const {},
  }) {
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed && !expand) {
      composer.selection = composer.selection!.collapseDownstream(editor.document);
      return true;
    }

    final currentExtent = composer.selection!.extent;
    final nodeId = currentExtent.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    final extentComponent = documentLayoutResolver().getComponentByNodeId(nodeId);
    if (extentComponent == null) {
      return false;
    }

    String newExtentNodeId = nodeId;
    dynamic newExtentNodePosition = extentComponent.movePositionRight(currentExtent.nodePosition, movementModifiers);

    if (newExtentNodePosition == null) {
      // Move to next node
      final nextNode = editor.document.getNodeAfter(node);

      if (nextNode == null) {
        // We're at the beginning/end of the document and can't go
        // anywhere.
        return false;
      }

      newExtentNodeId = nextNode.id;
      final nextComponent = documentLayoutResolver().getComponentByNodeId(nextNode.id);
      if (nextComponent == null) {
        throw Exception(
            'Could not find next component to move the selection horizontally. Next node ID: ${nextNode.id}');
      }
      newExtentNodePosition = nextComponent.getBeginningPosition();
    }

    final newExtent = DocumentPosition(
      nodeId: newExtentNodeId,
      nodePosition: newExtentNodePosition,
    );

    if (expand) {
      // Selection should be expanded.
      composer.selection = composer.selection!.expandTo(
        newExtent,
      );
    } else {
      // Selection should be replaced by new collapsed position.
      composer.selection = DocumentSelection.collapsed(
        position: newExtent,
      );
    }

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent position up,
  /// vertically, either by moving the selection extent up one line of
  /// text, or by moving the selection extent up to the node above the
  /// current extent.
  ///
  /// If the current selection extent wants to move to the node above,
  /// but there is no node above the current extent, the extent is moved
  /// to the "start" position of the current node. For example: the extent
  /// moves from the middle of the first line of text in a paragraph to
  /// the beginning of the paragraph.
  ///
  /// Expands/contracts the selection if [expand] is [true], otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// Returns [true] if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// [false] if the extent did not move and the selection did not change.
  bool moveCaretUp({
    bool expand = false,
  }) {
    if (composer.selection == null) {
      return false;
    }

    final currentExtent = composer.selection!.extent;
    final nodeId = currentExtent.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    final extentComponent = documentLayoutResolver().getComponentByNodeId(nodeId);
    if (extentComponent == null) {
      return false;
    }

    String newExtentNodeId = nodeId;
    dynamic newExtentNodePosition = extentComponent.movePositionUp(currentExtent.nodePosition);

    if (newExtentNodePosition == null) {
      // Move to next node
      final nextNode = editor.document.getNodeBefore(node);
      if (nextNode != null) {
        newExtentNodeId = nextNode.id;
        final nextComponent = documentLayoutResolver().getComponentByNodeId(nextNode.id);
        if (nextComponent == null) {
          return false;
        }
        final offsetToMatch = extentComponent.getOffsetForPosition(currentExtent.nodePosition);
        newExtentNodePosition = nextComponent.getEndPositionNearX(offsetToMatch.dx);
      } else {
        // We're at the top of the document. Move the cursor to the
        // beginning of the current node.
        newExtentNodePosition = extentComponent.getBeginningPosition();
      }
    }

    final newExtent = DocumentPosition(
      nodeId: newExtentNodeId,
      nodePosition: newExtentNodePosition,
    );

    if (expand) {
      // Selection should be expanded.
      composer.selection = composer.selection!.expandTo(
        newExtent,
      );
    } else {
      // Selection should be replaced by new collapsed position.
      composer.selection = DocumentSelection.collapsed(
        position: newExtent,
      );
    }

    return true;
  }

  /// Moves the [DocumentComposer]'s selection extent position down,
  /// vertically, either by moving the selection extent down one line of
  /// text, or by moving the selection extent down to the node below the
  /// current extent.
  ///
  /// If the current selection extent wants to move to the node below,
  /// but there is no node below the current extent, the extent is moved
  /// to the "end" position of the current node. For example: the extent
  /// moves from the middle of the last line of text in a paragraph to
  /// the end of the paragraph.
  ///
  /// Expands/contracts the selection if [expand] is [true], otherwise
  /// collapses the selection or keeps it collapsed.
  ///
  /// Returns [true] if the extent moved, or the selection changed, e.g., the
  /// selection collapsed but the extent stayed in the same place. Returns
  /// [false] if the extent did not move and the selection did not change.
  bool moveCaretDown({
    bool expand = false,
  }) {
    if (composer.selection == null) {
      return false;
    }

    final currentExtent = composer.selection!.extent;
    final nodeId = currentExtent.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    final extentComponent = documentLayoutResolver().getComponentByNodeId(nodeId);
    if (extentComponent == null) {
      return false;
    }

    String newExtentNodeId = nodeId;
    dynamic newExtentNodePosition = extentComponent.movePositionDown(currentExtent.nodePosition);

    if (newExtentNodePosition == null) {
      // Move to next node
      final nextNode = editor.document.getNodeAfter(node);
      if (nextNode != null) {
        newExtentNodeId = nextNode.id;
        final nextComponent = documentLayoutResolver().getComponentByNodeId(nextNode.id);
        if (nextComponent == null) {
          return false;
        }
        final offsetToMatch = extentComponent.getOffsetForPosition(currentExtent.nodePosition);
        newExtentNodePosition = nextComponent.getBeginningPositionNearX(offsetToMatch.dx);
      } else {
        // We're at the bottom of the document. Move the cursor to the
        // end of the current node.
        newExtentNodePosition = extentComponent.getEndPosition();
      }
    }

    final newExtent = DocumentPosition(
      nodeId: newExtentNodeId,
      nodePosition: newExtentNodePosition,
    );

    if (expand) {
      // Selection should be expanded.
      composer.selection = composer.selection!.expandTo(
        newExtent,
      );
    } else {
      // Selection should be replaced by new collapsed position.
      composer.selection = DocumentSelection.collapsed(
        position: newExtent,
      );
    }

    return true;
  }

  /// Deletes a unit of content that comes after the [DocumentComposer]'s
  /// selection extent, or deletes all selected content if the selection
  /// is not collapsed.
  ///
  /// In the case of text editing, deletes the character that appears after
  /// the caret.
  ///
  /// Returns [true] if content was deleted, or [false] if no downstream
  /// content exists.
  bool deleteDownstream() {
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed || composer.selection!.extent.nodePosition is BinaryNodePosition) {
      // A span of content is selected. Delete the selection.
      return deleteSelection();
    } else if (composer.selection!.extent.nodePosition is TextNodePosition) {
      final textPosition = composer.selection!.extent.nodePosition as TextNodePosition;
      final text = (editor.document.getNodeById(composer.selection!.extent.nodeId) as TextNode).text.text;
      if (textPosition.offset == text.length) {
        final node = editor.document.getNodeById(composer.selection!.extent.nodeId)!;
        final nodeAfter = editor.document.getNodeAfter(node);

        if (nodeAfter is TextNode) {
          // The caret is at the end of one TextNode and is followed by
          // another TextNode. Merge the two TextNodes.
          return _mergeTextNodeWithDownstreamTextNode();
        } else {
          // The caret is at the end of a TextNode, but the next node
          // is not a TextNode. Move the document selection to the
          // next node.
          return _moveSelectionToBeginningOfNextNode();
        }
      } else {
        return _deleteDownstreamCharacter();
      }
    }

    return false;
  }

  bool _moveSelectionToBeginningOfNextNode() {
    if (composer.selection == null) {
      return false;
    }

    final node = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (node == null) {
      return false;
    }

    final nodeAfter = editor.document.getNodeAfter(node);
    if (nodeAfter == null) {
      return false;
    }

    composer.selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: nodeAfter.id,
        nodePosition: nodeAfter.beginningPosition,
      ),
    );

    return true;
  }

  bool _mergeTextNodeWithDownstreamTextNode() {
    final node = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (node == null) {
      return false;
    }
    if (node is! TextNode) {
      return false;
    }

    final nodeAfter = editor.document.getNodeAfter(node);
    if (nodeAfter == null) {
      return false;
    }
    if (nodeAfter is! TextNode) {
      return false;
    }

    final firstNodeTextLength = node.text.text.length;

    // Send edit command.
    editor.executeCommand(
      CombineParagraphsCommand(
        firstNodeId: node.id,
        secondNodeId: nodeAfter.id,
      ),
    );

    // Place the cursor at the point where the text came together.
    composer.selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: node.id,
        nodePosition: TextNodePosition(offset: firstNodeTextLength),
      ),
    );

    return true;
  }

  bool _deleteDownstreamCharacter() {
    if (composer.selection == null) {
      return false;
    }
    if (!_isTextEntryNode(document: editor.document, selection: composer.selection!)) {
      return false;
    }
    if (composer.selection!.isCollapsed && (composer.selection!.extent.nodePosition as TextNodePosition).offset < 0) {
      return false;
    }

    final textNode = editor.document.getNode(composer.selection!.extent) as TextNode;
    final text = textNode.text;
    final currentTextPosition = (composer.selection!.extent.nodePosition as TextNodePosition);
    if (currentTextPosition.offset >= text.text.length) {
      return false;
    }

    final nextCharacterOffset = getCharacterEndBounds(text.text, currentTextPosition.offset);

    // Delete the selected content.
    editor.executeCommand(
      DeleteSelectionCommand(
        documentSelection: DocumentSelection(
          base: DocumentPosition(
            nodeId: textNode.id,
            nodePosition: currentTextPosition,
          ),
          extent: DocumentPosition(
            nodeId: textNode.id,
            nodePosition: TextNodePosition(offset: nextCharacterOffset),
          ),
        ),
      ),
    );

    return true;
  }

  /// Deletes a unit of content that comes before the [DocumentComposer]'s
  /// selection extent, or deletes all selected content if the selection
  /// is not collapsed.
  ///
  /// In the case of text editing, deletes the character that appears before
  /// the caret.
  ///
  /// Returns [true] if content was deleted, or [false] if no upstream
  /// content exists.
  bool deleteUpstream() {
    if (composer.selection == null) {
      return false;
    }

    if (!composer.selection!.isCollapsed || composer.selection!.extent.nodePosition is BinaryNodePosition) {
      // A span of content is selected. Delete the selection.
      return deleteSelection();
    }

    final node = editor.document.getNodeById(composer.selection!.extent.nodeId)!;

    // If the caret is at the beginning of a list item, unindent the list item.
    if (node is ListItemNode && (composer.selection!.extent.nodePosition as TextNodePosition).offset == 0) {
      return unindentListItem();
    }

    if (composer.selection!.extent.nodePosition is TextNodePosition) {
      final textPosition = composer.selection!.extent.nodePosition as TextNodePosition;
      if (textPosition.offset == 0) {
        final nodeBefore = editor.document.getNodeBefore(node);

        if (nodeBefore is TextNode) {
          // The caret is at the beginning of one TextNode and is preceded by
          // another TextNode. Merge the two TextNodes.
          return _mergeTextNodeWithUpstreamTextNode();
        } else if ((node as TextNode).text.text.isEmpty) {
          // The caret is at the beginning of an empty TextNode and the preceding
          // node is not a TextNode. Delete the current TextNode and move the
          // selection up to the preceding node.
          _moveSelectionToEndOfPrecedingNode();
          editor.executeCommand(EditorCommandFunction((doc, transaction) {
            transaction.deleteNode(node);
          }));
          return true;
        } else {
          // The caret is at the beginning of a non-empty TextNode, and the
          // preceding node is not a TextNode. Move the document selection to the
          // preceding node.
          return _moveSelectionToEndOfPrecedingNode();
        }
      } else {
        return _deleteUpstreamCharacter();
      }
    }

    return false;
  }

  bool _moveSelectionToEndOfPrecedingNode() {
    if (composer.selection == null) {
      return false;
    }

    final node = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (node == null) {
      return false;
    }

    final nodeBefore = editor.document.getNodeBefore(node);
    if (nodeBefore == null) {
      return false;
    }

    composer.selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: nodeBefore.id,
        nodePosition: nodeBefore.endPosition,
      ),
    );

    return true;
  }

  bool _mergeTextNodeWithUpstreamTextNode() {
    final node = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (node == null) {
      return false;
    }

    final nodeAbove = editor.document.getNodeBefore(node);
    if (nodeAbove == null) {
      return false;
    }
    if (nodeAbove is! TextNode) {
      return false;
    }

    final aboveParagraphLength = nodeAbove.text.text.length;

    // Send edit command.
    editor.executeCommand(
      CombineParagraphsCommand(
        firstNodeId: nodeAbove.id,
        secondNodeId: node.id,
      ),
    );

    // Place the cursor at the point where the text came together.
    composer.selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: nodeAbove.id,
        nodePosition: TextNodePosition(offset: aboveParagraphLength),
      ),
    );

    return true;
  }

  bool _deleteUpstreamCharacter() {
    if (composer.selection == null) {
      return false;
    }
    if (!_isTextEntryNode(document: editor.document, selection: composer.selection!)) {
      return false;
    }
    if (composer.selection!.isCollapsed && (composer.selection!.extent.nodePosition as TextNodePosition).offset <= 0) {
      return false;
    }

    final textNode = editor.document.getNode(composer.selection!.extent) as TextNode;
    final currentTextPosition = composer.selection!.extent.nodePosition as TextNodePosition;

    final previousCharacterOffset = getCharacterStartBounds(textNode.text.text, currentTextPosition.offset);

    final newSelectionPosition = DocumentPosition(
      nodeId: textNode.id,
      nodePosition: TextNodePosition(offset: previousCharacterOffset),
    );

    // Delete the selected content.
    editor.executeCommand(
      DeleteSelectionCommand(
        documentSelection: DocumentSelection(
          base: DocumentPosition(
            nodeId: textNode.id,
            nodePosition: currentTextPosition,
          ),
          extent: DocumentPosition(
            nodeId: textNode.id,
            nodePosition: TextNodePosition(offset: previousCharacterOffset),
          ),
        ),
      ),
    );

    composer.selection = DocumentSelection.collapsed(position: newSelectionPosition);

    return true;
  }

  /// Deletes all selected content.
  ///
  /// Returns [true] if content was deleted, or [false] if no content was
  /// selected.
  bool deleteSelection() {
    if (composer.selection == null) {
      return false;
    }

    if (composer.selection!.isCollapsed) {
      if (composer.selection!.extent.nodePosition is! BinaryNodePosition) {
        return false;
      }
      if (!(composer.selection!.extent.nodePosition as BinaryNodePosition).isIncluded) {
        return false;
      }

      // The document selection is collapsed, but the collapsed selection
      // currently selects a box node. Delete the box node.
      _deleteSelectedBox();
      return true;
    }

    // The document selection includes a span of content. It may or may not
    // cross nodes. Either way, delete the selected content.
    _deleteExpandedSelection();
    return true;
  }

  void _deleteSelectedBox() {
    final node = editor.document.getNode(composer.selection!.extent);
    if (node == null) {
      throw Exception(
          'Tried to delete a node but the selection extent doesn\'t exist in the document. Extent node: ${composer.selection!.extent}');
    }
    final deletedNodeIndex = editor.document.getNodeIndex(node);

    editor.executeCommand(
      DeleteSelectionCommand(
        documentSelection: composer.selection!,
      ),
    );

    final newSelectionPosition = _getAnotherSelectionAfterNodeDeletion(
      document: editor.document,
      documentLayout: documentLayoutResolver(),
      deletedNodeIndex: deletedNodeIndex,
    );

    composer.selection = newSelectionPosition != null
        ? DocumentSelection.collapsed(
            position: newSelectionPosition,
          )
        : null;
  }

  DocumentPosition? _getAnotherSelectionAfterNodeDeletion({
    required Document document,
    required DocumentLayout documentLayout,
    required int deletedNodeIndex,
  }) {
    if (deletedNodeIndex > 0) {
      final newSelectionNodeIndex = deletedNodeIndex - 1;
      final newSelectionNode = document.getNodeAt(newSelectionNodeIndex);
      if (newSelectionNode == null) {
        throw Exception(
            'Tried to access document node at index $newSelectionNodeIndex but the document returned null.');
      }
      final component = documentLayout.getComponentByNodeId(newSelectionNode.id);
      if (component == null) {
        throw Exception('Couldn\'t find editor component for node: ${newSelectionNode.id}');
      }
      return DocumentPosition(
        nodeId: newSelectionNode.id,
        nodePosition: component.getEndPosition(),
      );
    } else if (document.nodes.isNotEmpty) {
      // There is no node above the deleted node. It's at the top
      // of the document. Try to place the selection in whatever
      // is now the first node in the document.
      final newSelectionNode = document.getNodeAt(0);
      if (newSelectionNode == null) {
        throw Exception('Could not obtain the first node in a non-empty document.');
      }
      final component = documentLayout.getComponentByNodeId(newSelectionNode.id);
      if (component == null) {
        throw Exception('Couldn\'t find editor component for node: ${newSelectionNode.id}');
      }
      return DocumentPosition(
        nodeId: newSelectionNode.id,
        nodePosition: component.getBeginningPosition(),
      );
    } else {
      // The document is empty. Null out the position.
      return null;
    }
  }

  void _deleteExpandedSelection() {
    final newSelectionPosition = _getDocumentPositionAfterDeletion(
      document: editor.document,
      selection: composer.selection!,
    );

    // Delete the selected content.
    editor.executeCommand(
      DeleteSelectionCommand(documentSelection: composer.selection!),
    );

    composer.selection = DocumentSelection.collapsed(position: newSelectionPosition);
  }

  DocumentPosition _getDocumentPositionAfterDeletion({
    required Document document,
    required DocumentSelection selection,
  }) {
    // Figure out where the caret should appear after the
    // deletion.
    // TODO: This calculation depends upon the first
    //       selected node still existing after the deletion. This
    //       is a fragile expectation and should be revisited.
    final basePosition = selection.base;
    final baseNode = document.getNode(basePosition);
    if (baseNode == null) {
      throw Exception('Failed to _getDocumentPositionAfterDeletion because the base node no longer exists.');
    }
    final baseNodeIndex = document.getNodeIndex(baseNode);

    final extentPosition = selection.extent;
    final extentNode = document.getNode(extentPosition);
    if (extentNode == null) {
      throw Exception('Failed to _getDocumentPositionAfterDeletion because the extent node no longer exists.');
    }
    final extentNodeIndex = document.getNodeIndex(extentNode);
    DocumentPosition newSelectionPosition;

    if (baseNodeIndex != extentNodeIndex) {
      // Place the caret at the current position within the
      // first node in the selection.
      newSelectionPosition = baseNodeIndex <= extentNodeIndex ? selection.base : selection.extent;

      // If it's a binary selection node then that node will
      // be replaced by a ParagraphNode with the same ID.
      if (newSelectionPosition.nodePosition is BinaryNodePosition) {
        // Assume that the node was replaced with an empty paragraph.
        newSelectionPosition = DocumentPosition(
          nodeId: newSelectionPosition.nodeId,
          nodePosition: const TextNodePosition(offset: 0),
        );
      }
    } else {
      // Selection is within a single node. If it's a binary
      // selection node then that node will be replaced by
      // a ParagraphNode with the same ID. Otherwise, it must
      // be a TextNode, in which case we need to figure out
      // which DocumentPosition contains the earlier TextNodePosition.
      if (basePosition.nodePosition is BinaryNodePosition) {
        // Assume that the node was replace with an empty paragraph.
        newSelectionPosition = DocumentPosition(
          nodeId: baseNode.id,
          nodePosition: const TextNodePosition(offset: 0),
        );
      } else if (basePosition.nodePosition is TextNodePosition) {
        final baseOffset = (basePosition.nodePosition as TextNodePosition).offset;
        final extentOffset = (extentPosition.nodePosition as TextNodePosition).offset;

        newSelectionPosition = DocumentPosition(
          nodeId: baseNode.id,
          nodePosition: TextNodePosition(offset: min(baseOffset, extentOffset)),
        );
      } else {
        throw Exception(
            'Unknown selection position type: $basePosition, for node: $baseNode, within document selection: $selection');
      }
    }

    return newSelectionPosition;
  }

  /// Adds the given [attributions] to all [AttributedText] within the
  /// [DocumentComposer]'s current selection.
  ///
  /// Returns [true] if any text exists within the selection, or [false]
  /// otherwise.
  bool addAttributionsToSelection(Set<Attribution> attributions) {
    if (composer.selection == null) {
      return false;
    }

    if (composer.selection!.isCollapsed) {
      return false;
    }

    editor.executeCommand(
      AddTextAttributionsCommand(
        documentSelection: composer.selection!,
        attributions: attributions,
      ),
    );

    return false;
  }

  /// Removes the given [attributions] from all [AttributedText] within the
  /// [DocumentComposer]'s current selection.
  ///
  /// Returns [true] if any text exists within the selection, or [false]
  /// otherwise.
  bool removeAttributionsFromSelection(Set<Attribution> attributions) {
    if (composer.selection == null) {
      return false;
    }

    if (composer.selection!.isCollapsed) {
      return false;
    }

    editor.executeCommand(
      RemoveTextAttributionsCommand(
        documentSelection: composer.selection!,
        attributions: attributions,
      ),
    );

    return false;
  }

  /// Toggles the given [attributions] on all [AttributedText] within the
  /// [DocumentComposer]'s current selection.
  ///
  /// Returns [true] if any text exists within the selection, or [false]
  /// otherwise.
  bool toggleAttributionsOnSelection(Set<Attribution> attributions) {
    if (composer.selection == null) {
      return false;
    }

    if (composer.selection!.isCollapsed) {
      return false;
    }

    editor.executeCommand(
      ToggleTextAttributionsCommand(
        documentSelection: composer.selection!,
        attributions: attributions,
      ),
    );

    return false;
  }

  /// Adds the given [attributions] to the [DocumentComposer]'s input
  /// mode so that any new plain text inserted using [insertPlainText()]
  /// will contain the given [attributions].
  ///
  /// Always returns [true].
  bool activateComposerAttributions(Set<Attribution> attributions) {
    composer.preferences.addStyles(attributions);
    return true;
  }

  /// Removes the given [attributions] from the [DocumentComposer]'s input
  /// mode so that any new plain text inserted using [insertPlainText()]
  /// **doesn't** contain the given [attributions].
  ///
  /// Always returns [true].
  bool deactivateComposerAttributions(Set<Attribution> attributions) {
    composer.preferences.removeStyles(attributions);
    return true;
  }

  /// Toggles the presence of the given [attributions] within the
  /// [DocumentComposer]'s input mode.
  ///
  /// Always returns [true].
  bool toggleComposerAttributions(Set<Attribution> attributions) {
    composer.preferences.toggleStyles(attributions);
    return true;
  }

  /// Removes all [attributions] within the [DocumentComposer]'s
  /// input mode.
  ///
  /// Always returns [true].
  bool clearComposerAttributions() {
    composer.preferences.clearStyles();
    return true;
  }

  /// Inserts the given [text] at the [DocumentComposer]'s current
  /// selection extent, applying any [Attribution]s that are
  /// currently activated in the [DocumentComposer]'s input mode.
  ///
  /// Any selected content is deleted before inserting the new text.
  ///
  /// Returns [true] if the [text] was successfully inserted, or [false]
  /// if it wasn't, e.g., the currently selected node is not a [TextNode].
  bool insertPlainText(String text) {
    if (composer.selection == null) {
      return false;
    }

    final baseNode = editor.document.getNodeById(composer.selection!.base.nodeId)!;
    final extentNode = editor.document.getNodeById(composer.selection!.extent.nodeId)!;
    if (baseNode.id != extentNode.id) {
      return false;
    }
    if (extentNode is! TextNode) {
      return false;
    }

    if (!composer.selection!.isCollapsed) {
      // The selection is expanded. Delete the selected content
      // and then insert the new text.
      deleteSelection();
    }

    final textNode = editor.document.getNode(composer.selection!.extent) as TextNode;
    final initialTextOffset = (composer.selection!.extent.nodePosition as TextNodePosition).offset;

    editor.executeCommand(
      InsertTextCommand(
        documentPosition: composer.selection!.extent,
        textToInsert: text,
        attributions: composer.preferences.currentAttributions,
      ),
    );

    composer.selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: textNode.id,
        nodePosition: TextNodePosition(
          offset: initialTextOffset + 1,
        ),
      ),
    );

    return true;
  }

  /// Inserts the given [character] at the current extent position.
  ///
  /// By default, the current [DocumentComposer] input mode's [Attribution]s
  /// are added to the given [character]. To insert [character] exactly as it's provided,
  /// set [ignoreComposerAttributions] to [true].
  ///
  /// If the current selection is expanded, the current selection is deleted
  /// before the character is inserted.
  ///
  /// Returns [true] if the [character] was successfully inserted, or [false]
  /// if it wasn't, e.g., the currently selected node is not a [TextNode].
  bool insertCharacter(
    String character, {
    bool ignoreComposerAttributions = false,
  }) {
    if (composer.selection == null) {
      return false;
    }

    final node = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (node is! TextNode) {
      return false;
    }

    if (!composer.selection!.isCollapsed) {
      deleteSelection();
    }

    // Delegate the action to the standard insert-character behavior.
    final inserted = _insertCharacterInTextComposable(character);
    if (!inserted) {
      return false;
    }

    return true;
  }

  // TODO: refactor to make prefix matching extensible (#68)
  bool convertParagraphByPatternMatching(String nodeId) {
    final node = editor.document.getNodeById(nodeId);
    if (node == null) {
      return false;
    }
    if (node is! ParagraphNode) {
      return false;
    }

    final text = node.text;
    final textSelection = composer.selection!.extent.nodePosition as TextNodePosition;
    final textBeforeCaret = text.text.substring(0, textSelection.offset);

    final unorderedListItemMatch = RegExp(r'^\s*[\*-]\s+$');
    final hasUnorderedListItemMatch = unorderedListItemMatch.hasMatch(textBeforeCaret);

    final orderedListItemMatch = RegExp(r'^\s*[1].*\s+$');
    final hasOrderedListItemMatch = orderedListItemMatch.hasMatch(textBeforeCaret);

    _log.log('_convertParagraphIfDesired', ' - text before caret: "$textBeforeCaret"');
    if (hasUnorderedListItemMatch || hasOrderedListItemMatch) {
      _log.log('_convertParagraphIfDesired', ' - found unordered list item prefix');
      int startOfNewText = textBeforeCaret.length;
      while (startOfNewText < node.text.text.length && node.text.text[startOfNewText] == ' ') {
        startOfNewText += 1;
      }
      final adjustedText = node.text.copyText(startOfNewText);
      final newNode = hasUnorderedListItemMatch
          ? ListItemNode.unordered(id: node.id, text: adjustedText)
          : ListItemNode.ordered(id: node.id, text: adjustedText);
      final nodeIndex = editor.document.getNodeIndex(node);

      editor.executeCommand(
        EditorCommandFunction((document, transaction) {
          transaction
            ..deleteNodeAt(nodeIndex)
            ..insertNodeAt(nodeIndex, newNode);
        }),
      );

      // We removed some text at the beginning of the list item.
      // Move the selection back by that same amount.
      final textPosition = composer.selection!.extent.nodePosition as TextNodePosition;
      composer.selection = DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: textPosition.offset - startOfNewText),
        ),
      );

      return true;
    }

    final hrMatch = RegExp(r'^---*\s$');
    final hasHrMatch = hrMatch.hasMatch(textBeforeCaret);
    if (hasHrMatch) {
      _log.log('_convertParagraphIfDesired', 'Paragraph has an HR match');
      // Insert an HR before this paragraph and then clear the
      // paragraph's content.
      final paragraphNodeIndex = editor.document.getNodeIndex(node);

      editor.executeCommand(
        EditorCommandFunction((document, transaction) {
          transaction.insertNodeAt(
            paragraphNodeIndex,
            HorizontalRuleNode(
              id: DocumentEditor.createNodeId(),
            ),
          );
        }),
      );

      node.text = node.text.removeRegion(startOffset: 0, endOffset: hrMatch.firstMatch(textBeforeCaret)!.end);

      composer.selection = DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: node.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
      );

      return true;
    }

    final blockquoteMatch = RegExp(r'^>\s$');
    final hasBlockquoteMatch = blockquoteMatch.hasMatch(textBeforeCaret);
    if (hasBlockquoteMatch) {
      int startOfNewText = textBeforeCaret.length;
      while (startOfNewText < node.text.text.length && node.text.text[startOfNewText] == ' ') {
        startOfNewText += 1;
      }
      final adjustedText = node.text.copyText(startOfNewText);
      final newNode = ParagraphNode(
        id: node.id,
        text: adjustedText,
        metadata: {'blockType': blockquoteAttribution},
      );
      final nodeIndex = editor.document.getNodeIndex(node);

      editor.executeCommand(
        EditorCommandFunction((document, transaction) {
          transaction
            ..deleteNodeAt(nodeIndex)
            ..insertNodeAt(nodeIndex, newNode);
        }),
      );

      // We removed some text at the beginning of the list item.
      // Move the selection back by that same amount.
      final textPosition = composer.selection!.extent.nodePosition as TextNodePosition;
      composer.selection = DocumentSelection.collapsed(
        position: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: textPosition.offset - startOfNewText),
        ),
      );

      return true;
    }

    // URL match, e.g., images, social, etc.
    _log.log('_convertParagraphIfDesired', 'Looking for URL match...');
    final extractedLinks = linkify(node.text.text,
        options: const LinkifyOptions(
          humanize: false,
        ));
    final int linkCount = extractedLinks.fold(0, (value, element) => element is UrlElement ? value + 1 : value);
    final String nonEmptyText =
        extractedLinks.fold('', (value, element) => element is TextElement ? value + element.text.trim() : value);
    if (linkCount == 1 && nonEmptyText.isEmpty) {
      // This node's text is just a URL, try to interpret it
      // as a known type.
      final link = extractedLinks.firstWhereOrNull((element) => element is UrlElement)!.text;
      _processUrlNode(
        document: editor.document,
        editor: editor,
        nodeId: node.id,
        originalText: node.text.text,
        url: link,
      );
      return true;
    }

    // No pattern match was found
    return false;
  }

  Future<void> _processUrlNode({
    required Document document,
    required DocumentEditor editor,
    required String nodeId,
    required String originalText,
    required String url,
  }) async {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _log.log('_processUrlNode', 'Failed to load URL: ${response.statusCode} - ${response.reasonPhrase}');
      return;
    }

    final contentType = response.headers['content-type'];
    if (contentType == null) {
      _log.log('_processUrlNode', 'Failed to determine URL content type.');
      return;
    }
    if (!contentType.startsWith('image/')) {
      _log.log('_processUrlNode', 'URL is not an image. Ignoring');
      return;
    }

    // The URL is an image. Convert the node.
    _log.log('_processUrlNode', 'The URL is an image. Converting the ParagraphNode to an ImageNode.');
    final node = document.getNodeById(nodeId);
    if (node is! ParagraphNode) {
      _log.log(
          '_processUrlNode', 'The node has become something other than a ParagraphNode ($node). Can\'t convert ndoe.');
      return;
    }
    final currentText = node.text.text;
    if (currentText.trim() != originalText.trim()) {
      _log.log('_processUrlNode', 'The node content changed in a non-trivial way. Aborting node conversion.');
      return;
    }

    final imageNode = ImageNode(
      id: node.id,
      imageUrl: url,
    );
    final nodeIndex = document.getNodeIndex(node);

    editor.executeCommand(
      EditorCommandFunction((document, transaction) {
        transaction
          ..deleteNodeAt(nodeIndex)
          ..insertNodeAt(nodeIndex, imageNode);
      }),
    );

    composer.selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: node.id,
        nodePosition: imageNode.endPosition,
      ),
    );
  }

  bool _insertCharacterInTextComposable(
    String character, {
    bool ignoreComposerAttributions = false,
  }) {
    if (composer.selection == null) {
      return false;
    }
    if (!composer.selection!.isCollapsed) {
      return false;
    }
    if (!_isTextEntryNode(document: editor.document, selection: composer.selection!)) {
      return false;
    }

    final textNode = editor.document.getNode(composer.selection!.extent) as TextNode;
    final initialTextOffset = (composer.selection!.extent.nodePosition as TextNodePosition).offset;

    editor.executeCommand(
      InsertTextCommand(
        documentPosition: composer.selection!.extent,
        textToInsert: character,
        attributions: ignoreComposerAttributions ? {} : composer.preferences.currentAttributions,
      ),
    );

    composer.selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: textNode.id,
        nodePosition: TextNodePosition(
          offset: initialTextOffset + character.length,
        ),
      ),
    );

    return true;
  }

  /// Inserts a new [ParagraphNode], or splits an existing node into two.
  ///
  /// If the [DocumentComposer] selection is collapsed, and the extent is
  /// at the end of a node, such as the end of a paragraph, then a new
  /// [ParagraphNode] is added after the current node and the selection
  /// extent is moved to the new [ParagraphNode].
  ///
  /// If the [DocumentComposer] selection is collapsed, and the extent is
  /// in the middle of a node, such as in the middle of a paragraph, list
  /// item, or blockquote, then the current node is split into two nodes
  /// of the same type at that position.
  ///
  /// If the current selection is not collapsed then the current selection
  /// is first deleted, then the aforementioned operation takes place.
  ///
  /// Returns [true] if a new node was inserted or a node was split into two.
  /// Returns [false] if there was no selection.
  bool insertBlockLevelNewline() {
    if (composer.selection == null) {
      return false;
    }

    // Ensure that the entire selection sits within the same node.
    final baseNode = editor.document.getNodeById(composer.selection!.base.nodeId)!;
    final extentNode = editor.document.getNodeById(composer.selection!.extent.nodeId)!;
    if (baseNode.id != extentNode.id) {
      return false;
    }

    if (!composer.selection!.isCollapsed) {
      // The selection is not collapsed. Delete the selected content first,
      // then continue the process.
      deleteSelection();
    }

    final newNodeId = DocumentEditor.createNodeId();

    if (extentNode is ListItemNode) {
      if (extentNode.text.text.isEmpty) {
        // The list item is empty. Convert it to a paragraph.
        return convertToParagraph();
      }

      // Split the list item into two.
      editor.executeCommand(
        SplitListItemCommand(
          nodeId: extentNode.id,
          splitPosition: composer.selection!.extent.nodePosition as TextNodePosition,
          newNodeId: newNodeId,
        ),
      );
    } else if (extentNode is ParagraphNode) {
      // Split the paragraph into two. This includes headers, blockquotes, and
      // any other block-level paragraph.
      final currentExtentPosition = composer.selection!.extent.nodePosition as TextNodePosition;
      final endOfParagraph = extentNode.endPosition;

      editor.executeCommand(
        SplitParagraphCommand(
          nodeId: extentNode.id,
          splitPosition: currentExtentPosition,
          newNodeId: newNodeId,
          replicateExistingMetdata: currentExtentPosition.offset != endOfParagraph.offset,
        ),
      );
    } else {
      // The selection extent might be an image, HR, etc. Insert a new
      // node after it.
      editor.executeCommand(EditorCommandFunction((doc, transaction) {
        transaction.insertNodeAfter(
          previousNode: extentNode,
          newNode: ParagraphNode(
            id: newNodeId,
            text: AttributedText(text: ''),
          ),
        );
      }));
    }

    // Place the caret at the beginning of the second node.
    composer.selection = DocumentSelection.collapsed(
      position: DocumentPosition(
        nodeId: newNodeId,
        nodePosition: const TextNodePosition(offset: 0),
      ),
    );

    return true;
  }

  /// Inserts an image at the current selection extent.
  ///
  /// If the selection extent sits in an empty paragraph, that paragraph
  /// is converted into the desired image and a new empty paragraph is inserted
  /// after the image.
  ///
  /// If the selection extent sits at the end of a paragraph, the image is
  /// inserted as a new node after that paragraph, and then a new empty paragraph
  /// is inserted after the image.
  ///
  /// If the selection extent sits in the middle of a paragraph then the
  /// paragraph is split into two at that position, an image is inserted between
  /// the two paragraphs, the selection extent is placed at the beginning of the
  /// second paragraph.
  ///
  /// If the selection extent sits in any other kind of node, nothing happens.
  ///
  /// Returns [true] if an image was inserted, [false] if it wasn't.
  bool insertImage(String url) {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.nodeId != composer.selection!.extent.nodeId) {
      return false;
    }

    final nodeId = composer.selection!.base.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node is! ParagraphNode) {
      return false;
    }

    editor.executeCommand(
      EditorCommandFunction((document, transaction) {
        final paragraphPosition = composer.selection!.extent.nodePosition as TextNodePosition;
        final endOfParagraph = node.endPosition;

        final nodeIndex = editor.document.getNodeIndex(node);

        DocumentSelection newSelection;
        if (node.text.text.isEmpty) {
          // Convert empty paragraph to HR.
          final imageNode = ImageNode(id: nodeId, imageUrl: url);

          transaction
            ..deleteNodeAt(nodeIndex)
            ..insertNodeAt(nodeIndex, imageNode);

          newSelection = DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: nodeId,
              nodePosition: imageNode.endPosition,
            ),
          );
        } else if (paragraphPosition == endOfParagraph) {
          // Insert HR after the paragraph.
          final imageNode = ImageNode(id: DocumentEditor.createNodeId(), imageUrl: url);

          transaction.insertNodeAfter(previousNode: node, newNode: imageNode);

          newSelection = DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: nodeId,
              nodePosition: imageNode.endPosition,
            ),
          );
        } else {
          // Split the paragraph and inset HR in between.
          final textBefore = node.text.copyText(0, paragraphPosition.offset);
          final textAfter = node.text.copyText(paragraphPosition.offset);

          final imageNode = ImageNode(id: nodeId, imageUrl: url);
          final newParagraph = ParagraphNode(id: DocumentEditor.createNodeId(), text: textAfter);

          // TODO: node operations need to be a part of a transaction, somehow.
          node.text = textBefore;
          transaction
            ..insertNodeAfter(previousNode: node, newNode: imageNode)
            ..insertNodeAfter(previousNode: imageNode, newNode: newParagraph);

          newSelection = DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: nodeId,
              nodePosition: newParagraph.beginningPosition,
            ),
          );
        }

        composer.selection = newSelection;
      }),
    );

    return true;
  }

  /// Inserts horizontal rule at the current selection extent.
  ///
  /// If the selection extent sits in an empty paragraph, that paragraph
  /// is converted into the desired horizontal rule and a new empty paragraph
  /// is inserted after the horizontal rule.
  ///
  /// If the selection extent sits at the end of a paragraph, the horizontal
  /// rule is inserted as a new node after that paragraph, and then a new
  /// empty paragraph is inserted after the image.
  ///
  /// If the selection extent sits in the middle of a paragraph then the
  /// paragraph is split into two at that position, a horizontal rule is
  /// inserted between the two paragraphs, the selection extent is placed
  /// at the beginning of the second paragraph.
  ///
  /// If the selection extent sits in any other kind of node, nothing happens.
  ///
  /// Returns [true] if a horizontal rule was inserted, [false] if it wasn't.
  bool insertHorizontalRule() {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.nodeId != composer.selection!.extent.nodeId) {
      return false;
    }

    final nodeId = composer.selection!.base.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node is! ParagraphNode) {
      return false;
    }

    final nodeIndex = editor.document.getNodeIndex(node);

    editor.executeCommand(
      EditorCommandFunction((document, transaction) {
        final paragraphPosition = composer.selection!.extent.nodePosition as TextNodePosition;
        final endOfParagraph = node.endPosition;

        DocumentSelection newSelection;
        if (node.text.text.isEmpty) {
          // Convert empty paragraph to HR.
          final hrNode = HorizontalRuleNode(id: nodeId);

          transaction
            ..deleteNodeAt(nodeIndex)
            ..insertNodeAt(nodeIndex, hrNode);

          newSelection = DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: nodeId,
              nodePosition: hrNode.endPosition,
            ),
          );
        } else if (paragraphPosition == endOfParagraph) {
          // Insert HR after the paragraph.
          final hrNode = HorizontalRuleNode(id: DocumentEditor.createNodeId());

          transaction.insertNodeAfter(previousNode: node, newNode: hrNode);

          newSelection = DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: nodeId,
              nodePosition: hrNode.endPosition,
            ),
          );
        } else {
          // Split the paragraph and inset HR in between.
          final textBefore = node.text.copyText(0, paragraphPosition.offset);
          final textAfter = node.text.copyText(paragraphPosition.offset);

          final hrNode = HorizontalRuleNode(id: DocumentEditor.createNodeId());
          final newParagraph = ParagraphNode(id: DocumentEditor.createNodeId(), text: textAfter);

          // TODO: node operations need to be a part of a transaction, somehow.
          node.text = textBefore;
          transaction
            ..insertNodeAfter(previousNode: node, newNode: hrNode)
            ..insertNodeAfter(previousNode: hrNode, newNode: newParagraph);

          newSelection = DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: nodeId,
              nodePosition: newParagraph.beginningPosition,
            ),
          );
        }

        composer.selection = newSelection;
      }),
    );

    return true;
  }

  /// Indents the list item at the current selection extent, if the entire
  /// selection sits within a [ListItemNode].
  ///
  /// Returns [true] if a list item was indented. Returns [false] if
  /// the selection extent did not sit in a list item, or if the selection
  /// included more than just a list item.
  bool indentListItem() {
    if (composer.selection == null) {
      return false;
    }

    final baseNode = editor.document.getNodeById(composer.selection!.base.nodeId);
    final extentNode = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (baseNode is! ListItemNode || extentNode is! ListItemNode) {
      return false;
    }

    editor.executeCommand(
      IndentListItemCommand(nodeId: extentNode.id),
    );

    return true;
  }

  /// Indents the list item at the current selection extent, if the entire
  /// selection sits within a [ListItemNode].
  ///
  /// If the list item is not indented, the list item is converted to
  /// a [ParagraphNode].
  ///
  /// Returns [true] if a list item was un-indented. Returns [false] if
  /// the selection extent did not sit in a list item, or if the selection
  /// included more than just a list item.
  bool unindentListItem() {
    if (composer.selection == null) {
      return false;
    }

    final baseNode = editor.document.getNodeById(composer.selection!.base.nodeId);
    final extentNode = editor.document.getNodeById(composer.selection!.extent.nodeId);
    if (baseNode!.id != extentNode!.id) {
      return false;
    }

    editor.executeCommand(
      UnIndentListItemCommand(nodeId: extentNode.id),
    );

    return true;
  }

  /// Converts the [TextNode] with the current [DocumentComposer] selection
  /// extent to a [ListItemNode] of the given [type], or does nothing if the
  /// current node is not a [TextNode], or if the current selection spans
  /// more than one node.
  ///
  /// Returns [true] if the selected node was converted to a [ListItemNode],
  /// or [false] if it wasn't.
  bool convertToListItem(ListItemType type, AttributedText text) {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.nodeId != composer.selection!.extent.nodeId) {
      return false;
    }

    final nodeId = composer.selection!.base.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node is! TextNode) {
      return false;
    }

    final nodeIndex = editor.document.getNodeIndex(node);
    final newNode = ListItemNode(id: nodeId, itemType: type, text: text);

    editor.executeCommand(
      EditorCommandFunction((document, transaction) {
        transaction
          ..deleteNodeAt(nodeIndex)
          ..insertNodeAt(nodeIndex, newNode);

        composer.selection = DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: nodeId,
            nodePosition: newNode.endPosition,
          ),
        );
      }),
    );

    return true;
  }

  /// Converts the [TextNode] with the current [DocumentComposer] selection
  /// extent to a [Paragraph] with a blockquote block type, or does nothing
  /// if the current node is not a [TextNode], or if the current selection
  /// spans more than one node.
  ///
  /// Returns [true] if the selected node was converted to a blockquote,
  /// or [false] if it wasn't.
  bool convertToBlockquote(AttributedText text) {
    if (composer.selection == null) {
      return false;
    }
    if (composer.selection!.base.nodeId != composer.selection!.extent.nodeId) {
      return false;
    }

    final nodeId = composer.selection!.base.nodeId;
    final node = editor.document.getNodeById(nodeId);
    if (node is! TextNode) {
      return false;
    }

    final nodeIndex = editor.document.getNodeIndex(node);
    final newNode = ParagraphNode(id: nodeId, metadata: {'blockType': blockquoteAttribution}, text: text);

    editor.executeCommand(
      EditorCommandFunction((document, transaction) {
        transaction
          ..deleteNodeAt(nodeIndex)
          ..insertNodeAt(nodeIndex, newNode);

        composer.selection = DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: nodeId,
            nodePosition: newNode.endPosition,
          ),
        );
      }),
    );

    return true;
  }

  /// Converts the [TextNode] with the current [DocumentComposer] selection
  /// extent to a [Paragraph], or does nothing if the current node is not
  /// a [TextNode], or if the current selection spans more than one node.
  ///
  /// Returns [true] if the selected node was converted to a [ParagraphNode],
  /// or [false] if it wasn't.
  bool convertToParagraph() {
    if (composer.selection == null) {
      return false;
    }

    final baseNode = editor.document.getNodeById(composer.selection!.base.nodeId)!;
    final extentNode = editor.document.getNodeById(composer.selection!.extent.nodeId)!;
    if (baseNode.id != extentNode.id) {
      return false;
    }
    if (extentNode is! TextNode) {
      return false;
    }
    if (extentNode is ParagraphNode && !extentNode.metadata.containsKey('blockType')) {
      // This content is already a regular paragraph.
      return false;
    }

    editor.executeCommand(
      EditorCommandFunction((document, transaction) {
        if (extentNode is ParagraphNode) {
          extentNode.metadata.remove('blockType');
          // TODO: find a way to alter nodes that automatically notifies listeners
          // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
          extentNode.notifyListeners();
        } else {
          final newParagraphNode = ParagraphNode(
            id: extentNode.id,
            text: extentNode.text,
          );
          final extentNodeIndex = document.getNodeIndex(extentNode);

          transaction
            ..deleteNodeAt(extentNodeIndex)
            ..insertNodeAt(extentNodeIndex, newParagraphNode);
        }
      }),
    );

    return true;
  }

  bool _isTextEntryNode({
    required Document document,
    required DocumentSelection selection,
  }) {
    final extentPosition = selection.extent;
    final extentNode = document.getNodeById(extentPosition.nodeId);
    return extentNode is TextNode;
  }
}
