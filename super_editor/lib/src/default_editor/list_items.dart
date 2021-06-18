import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/attributed_text.dart';
import 'package:super_editor/super_editor.dart';

import '../core/document.dart';
import '../core/document_editor.dart';
import 'document_interaction.dart';
import 'paragraph.dart';
import 'styles.dart';
import 'text.dart';

final _log = Logger(scope: 'list_items.dart');

class ListItemNode extends TextNode {
  ListItemNode.ordered({
    required String id,
    required AttributedText text,
    Map<String, dynamic>? metadata,
    int indent = 0,
  })  : type = ListItemType.ordered,
        _indent = indent,
        super(
          id: id,
          text: text,
          metadata: metadata,
        );

  ListItemNode.unordered({
    required String id,
    required AttributedText text,
    Map<String, dynamic>? metadata,
    int indent = 0,
  })  : type = ListItemType.unordered,
        _indent = indent,
        super(
          id: id,
          text: text,
          metadata: metadata,
        );

  ListItemNode({
    required String id,
    required ListItemType itemType,
    required AttributedText text,
    Map<String, dynamic>? metadata,
    int indent = 0,
  })  : type = itemType,
        _indent = indent,
        super(
          id: id,
          text: text,
          metadata: metadata,
        );

  final ListItemType type;

  int _indent;
  int get indent => _indent;
  set indent(int newIndent) {
    if (newIndent != _indent) {
      _indent = newIndent;
      notifyListeners();
    }
  }

  @override
  bool hasEquivalentContent(DocumentNode other) {
    return other is ListItemNode && type == other.type && indent == other.indent && text == other.text;
  }
}

enum ListItemType {
  ordered,
  unordered,
}

/// Displays a un-ordered list item in a document.
///
/// Supports various indentation levels, e.g., 1, 2, 3, ...
class UnorderedListItemComponent extends StatelessWidget {
  const UnorderedListItemComponent({
    Key? key,
    required this.textKey,
    required this.text,
    required this.styleBuilder,
    this.dotBuilder = _defaultUnorderedListItemDotBuilder,
    this.indent = 0,
    this.indentExtent = 25,
    this.textSelection,
    this.selectionColor = Colors.lightBlueAccent,
    this.showCaret = false,
    this.caretColor = Colors.black,
    this.showDebugPaint = false,
  }) : super(key: key);

  final GlobalKey textKey;
  final AttributedText text;
  final AttributionStyleBuilder styleBuilder;
  final UnorderedListItemDotBuilder dotBuilder;
  final int indent;
  final double indentExtent;
  final TextSelection? textSelection;
  final Color selectionColor;
  final bool showCaret;
  final Color caretColor;
  final bool showDebugPaint;

  @override
  Widget build(BuildContext context) {
    final indentSpace = indentExtent * (indent + 1);
    final firstLineHeight = styleBuilder({}).fontSize;
    const manualVerticalAdjustment = 2.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: manualVerticalAdjustment),
          decoration: BoxDecoration(
            border: Border.all(width: 1, color: showDebugPaint ? Colors.grey : Colors.transparent),
          ),
          child: SizedBox(
            width: indentSpace,
            height: firstLineHeight,
            child: dotBuilder(context, this),
          ),
        ),
        Expanded(
          child: TextComponent(
            key: textKey,
            text: text,
            textStyleBuilder: styleBuilder,
            textSelection: textSelection,
            selectionColor: selectionColor,
            showCaret: showCaret,
            caretColor: caretColor,
            showDebugPaint: showDebugPaint,
          ),
        ),
      ],
    );
  }
}

typedef UnorderedListItemDotBuilder = Widget Function(BuildContext, UnorderedListItemComponent);

Widget _defaultUnorderedListItemDotBuilder(BuildContext context, UnorderedListItemComponent component) {
  return Align(
    alignment: Alignment.centerRight,
    child: Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: component.styleBuilder({}).color,
      ),
    ),
  );
}

/// Displays an ordered list item in a document.
///
/// Supports various indentation levels, e.g., 1, 2, 3, ...
class OrderedListItemComponent extends StatelessWidget {
  const OrderedListItemComponent({
    Key? key,
    required this.textKey,
    required this.listIndex,
    required this.text,
    required this.styleBuilder,
    this.numeralBuilder = _defaultOrderedListItemNumeralBuilder,
    this.indent = 0,
    this.indentExtent = 25,
    this.textSelection,
    this.selectionColor = Colors.lightBlueAccent,
    this.showCaret = false,
    this.caretColor = Colors.black,
    this.showDebugPaint = false,
  }) : super(key: key);

  final GlobalKey textKey;
  final int listIndex;
  final AttributedText text;
  final AttributionStyleBuilder styleBuilder;
  final OrderedListItemNumeralBuilder numeralBuilder;
  final int indent;
  final double indentExtent;
  final TextSelection? textSelection;
  final Color selectionColor;
  final bool showCaret;
  final Color caretColor;
  final bool showDebugPaint;

  @override
  Widget build(BuildContext context) {
    final indentSpace = indentExtent * (indent + 1);
    final firstLineHeight = styleBuilder({}).fontSize!;
    const manualVerticalAdjustment = 2.0;
    final manualHeightAdjustment = firstLineHeight * 0.15;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: indentSpace,
          height: firstLineHeight + manualHeightAdjustment,
          margin: const EdgeInsets.only(top: manualVerticalAdjustment),
          decoration: BoxDecoration(
            border: Border.all(width: 1, color: showDebugPaint ? Colors.grey : Colors.transparent),
          ),
          child: SizedBox(
            width: indentSpace,
            height: firstLineHeight,
            child: numeralBuilder(context, this),
          ),
        ),
        Expanded(
          child: TextComponent(
            key: textKey,
            text: text,
            textStyleBuilder: styleBuilder,
            textSelection: textSelection,
            selectionColor: selectionColor,
            showCaret: showCaret,
            caretColor: caretColor,
            showDebugPaint: showDebugPaint,
          ),
        ),
      ],
    );
  }
}

typedef OrderedListItemNumeralBuilder = Widget Function(BuildContext, OrderedListItemComponent);

Widget _defaultOrderedListItemNumeralBuilder(BuildContext context, OrderedListItemComponent component) {
  return OverflowBox(
    maxHeight: double.infinity,
    child: Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 5.0),
        child: Text(
          '${component.listIndex}.',
          style: component.styleBuilder({}).copyWith(),
        ),
      ),
    ),
  );
}

class IndentListItemCommand implements EditorCommand {
  IndentListItemCommand({
    required this.nodeId,
  });

  final String nodeId;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    // TODO: figure out how node changes should work in terms of
    //       a DocumentEditorTransaction (#67)
    final node = document.getNodeById(nodeId);
    final listItem = node as ListItemNode;
    if (listItem.indent >= 6) {
      _log.log('IndentListItemCommand', 'WARNING: Editor does not support an indent level beyond 6.');
      return;
    }

    listItem.indent += 1;
  }
}

class UnIndentListItemCommand implements EditorCommand {
  UnIndentListItemCommand({
    required this.nodeId,
  });

  final String nodeId;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final node = document.getNodeById(nodeId);
    final listItem = node as ListItemNode;
    if (listItem.indent > 0) {
      // TODO: figure out how node changes should work in terms of
      //       a DocumentEditorTransaction (#67)
      listItem.indent -= 1;
    } else {
      ConvertListItemToParagraphCommand(
        nodeId: nodeId,
      ).execute(document, transaction);
    }
  }
}

class ConvertListItemToParagraphCommand implements EditorCommand {
  ConvertListItemToParagraphCommand({
    required this.nodeId,
    this.paragraphMetadata,
  });

  final String nodeId;
  final Map<String, dynamic>? paragraphMetadata;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final node = document.getNodeById(nodeId);
    final listItem = node as ListItemNode;

    final newParagraphNode = ParagraphNode(
      id: listItem.id,
      text: listItem.text,
      metadata: paragraphMetadata ?? {},
    );
    transaction.replaceNode(oldNode: listItem, newNode: newParagraphNode);
  }
}

class ConvertParagraphToListItemCommand implements EditorCommand {
  ConvertParagraphToListItemCommand({
    required this.nodeId,
    required this.type,
  });

  final String nodeId;
  final ListItemType type;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final node = document.getNodeById(nodeId);
    final paragraphNode = node as ParagraphNode;

    final newListItemNode = ListItemNode(
      id: paragraphNode.id,
      itemType: type,
      text: paragraphNode.text,
    );
    transaction.replaceNode(oldNode: paragraphNode, newNode: newListItemNode);
  }
}

class ChangeListItemTypeCommand implements EditorCommand {
  ChangeListItemTypeCommand({
    required this.nodeId,
    required this.newType,
  });

  final String nodeId;
  final ListItemType newType;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final existingListItem = document.getNodeById(nodeId) as ListItemNode;

    final newListItemNode = ListItemNode(
      id: existingListItem.id,
      itemType: newType,
      text: existingListItem.text,
    );
    transaction.replaceNode(oldNode: existingListItem, newNode: newListItemNode);
  }
}

class SplitListItemCommand implements EditorCommand {
  SplitListItemCommand({
    required this.nodeId,
    required this.splitPosition,
    required this.newNodeId,
  });

  final String nodeId;
  final TextPosition splitPosition;
  final String newNodeId;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final node = document.getNodeById(nodeId);
    final listItemNode = node as ListItemNode;
    final text = listItemNode.text;
    final startText = text.copyText(0, splitPosition.offset);
    final endText = splitPosition.offset < text.text.length ? text.copyText(splitPosition.offset) : AttributedText();
    _log.log('SplitListItemCommand', 'Splitting list item:');
    _log.log('SplitListItemCommand', ' - start text: "$startText"');
    _log.log('SplitListItemCommand', ' - end text: "$endText"');

    // Change the current node's content to just the text before the caret.
    _log.log('SplitListItemCommand', ' - changing the original list item text due to split');
    // TODO: figure out how node changes should work in terms of
    //       a DocumentEditorTransaction (#67)
    listItemNode.text = startText;

    // Create a new node that will follow the current node. Set its text
    // to the text that was removed from the current node.
    final newNode = listItemNode.type == ListItemType.ordered
        ? ListItemNode.ordered(
            id: newNodeId,
            text: endText,
            indent: listItemNode.indent,
          )
        : ListItemNode.unordered(
            id: newNodeId,
            text: endText,
            indent: listItemNode.indent,
          );

    // Insert the new node after the current node.
    _log.log('SplitListItemCommand', ' - inserting new node in document');
    transaction.insertNodeAfter(
      previousNode: node,
      newNode: newNode,
    );

    _log.log('SplitListItemCommand', ' - inserted new node: ${newNode.id} after old one: ${node.id}');
  }
}

ExecutionInstruction tabToIndentListItem({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.tab) {
    return ExecutionInstruction.continueExecution;
  }
  if (keyEvent.isShiftPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final wasIndented = editContext.commonOps.indentListItem();

  return wasIndented ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction shiftTabToUnIndentListItem({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.tab) {
    return ExecutionInstruction.continueExecution;
  }
  if (!keyEvent.isShiftPressed) {
    return ExecutionInstruction.continueExecution;
  }

  final wasIndented = editContext.commonOps.unindentListItem();

  return wasIndented ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction backspaceToUnIndentListItem({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.backspace) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }
  if (!editContext.composer.selection!.isCollapsed) {
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.editor.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! ListItemNode) {
    return ExecutionInstruction.continueExecution;
  }
  if ((editContext.composer.selection!.extent.nodePosition as TextPosition).offset > 0) {
    return ExecutionInstruction.continueExecution;
  }

  final wasIndented = editContext.commonOps.unindentListItem();

  return wasIndented ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction splitListItemWhenEnterPressed({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.enter) {
    return ExecutionInstruction.continueExecution;
  }

  final node = editContext.editor.document.getNodeById(editContext.composer.selection!.extent.nodeId);
  if (node is! ListItemNode) {
    return ExecutionInstruction.continueExecution;
  }

  final didSplitListItem = editContext.commonOps.insertBlockLevelNewline();
  return didSplitListItem ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

Widget? unorderedListItemBuilder(ComponentContext componentContext) {
  final listItemNode = componentContext.documentNode;
  if (listItemNode is! ListItemNode) {
    return null;
  }

  if (listItemNode.type != ListItemType.unordered) {
    return null;
  }

  final textSelection = componentContext.nodeSelection?.nodeSelection as TextSelection?;
  final showCaret = componentContext.showCaret && (componentContext.nodeSelection?.isExtent ?? false);

  return UnorderedListItemComponent(
    textKey: componentContext.componentKey,
    text: listItemNode.text,
    styleBuilder: componentContext.extensions[textStylesExtensionKey],
    indent: listItemNode.indent,
    textSelection: textSelection,
    selectionColor: (componentContext.extensions[selectionStylesExtensionKey] as SelectionStyle).selectionColor,
    showCaret: showCaret,
    caretColor: (componentContext.extensions[selectionStylesExtensionKey] as SelectionStyle).textCaretColor,
  );
}

Widget? orderedListItemBuilder(ComponentContext componentContext) {
  final listItemNode = componentContext.documentNode;
  if (listItemNode is! ListItemNode) {
    return null;
  }

  if (listItemNode.type != ListItemType.ordered) {
    return null;
  }

  int index = 1;
  DocumentNode? nodeAbove = componentContext.document.getNodeBefore(listItemNode);
  while (nodeAbove != null &&
      nodeAbove is ListItemNode &&
      nodeAbove.type == ListItemType.ordered &&
      nodeAbove.indent >= listItemNode.indent) {
    if (nodeAbove.indent == listItemNode.indent) {
      index += 1;
    }
    nodeAbove = componentContext.document.getNodeBefore(nodeAbove);
  }

  final textSelection = componentContext.nodeSelection?.nodeSelection as TextSelection?;
  final showCaret = componentContext.showCaret && (componentContext.nodeSelection?.isExtent ?? false);

  return OrderedListItemComponent(
    textKey: componentContext.componentKey,
    listIndex: index,
    text: listItemNode.text,
    styleBuilder: componentContext.extensions[textStylesExtensionKey],
    textSelection: textSelection,
    selectionColor: (componentContext.extensions[selectionStylesExtensionKey] as SelectionStyle).selectionColor,
    showCaret: showCaret,
    caretColor: (componentContext.extensions[selectionStylesExtensionKey] as SelectionStyle).textCaretColor,
    indent: listItemNode.indent,
  );
}
