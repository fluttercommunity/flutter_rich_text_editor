import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/src/core/document_layout.dart';
import 'package:super_editor/src/core/edit_context.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';
import 'package:super_editor/src/infrastructure/attributed_text.dart';

import '../core/document.dart';
import '../core/document_editor.dart';
import 'document_interaction.dart';
import 'paragraph.dart';
import 'styles.dart';
import 'text.dart';

// ignore: unused_element
final _log = Logger(scope: 'blockquote.dart');

/// Displays a blockquote in a document.
class BlockquoteComponent extends StatelessWidget {
  const BlockquoteComponent({
    Key? key,
    required this.textKey,
    required this.text,
    required this.styleBuilder,
    this.textSelection,
    this.selectionColor = Colors.lightBlueAccent,
    this.showCaret = false,
    this.caretColor = Colors.black,
    this.showDebugPaint = false,
  }) : super(key: key);

  final GlobalKey textKey;
  final AttributedText text;
  final AttributionStyleBuilder styleBuilder;
  final TextSelection? textSelection;
  final Color selectionColor;
  final bool showCaret;
  final Color caretColor;
  final bool showDebugPaint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: const Color(0xFFEEEEEE),
      ),
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
    );
  }
}

class ConvertBlockquoteToParagraphCommand implements EditorCommand {
  ConvertBlockquoteToParagraphCommand({
    required this.nodeId,
  });

  final String nodeId;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final node = document.getNodeById(nodeId);
    final blockquote = node as ParagraphNode;
    final newParagraphNode = ParagraphNode(
      id: blockquote.id,
      text: blockquote.text,
    );
    transaction.replaceNode(oldNode: blockquote, newNode: newParagraphNode);
  }
}

ExecutionInstruction insertNewlineInBlockquote({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.enter) {
    return ExecutionInstruction.continueExecution;
  }

  if (!keyEvent.isShiftPressed) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  final baseNode = editContext.editor.document.getNodeById(editContext.composer.selection!.base.nodeId)!;
  final extentNode = editContext.editor.document.getNodeById(editContext.composer.selection!.extent.nodeId)!;
  if (baseNode.id != extentNode.id) {
    return ExecutionInstruction.continueExecution;
  }
  if (extentNode is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }
  if (extentNode.metadata['blockType'] != blockquoteAttribution) {
    return ExecutionInstruction.continueExecution;
  }

  final didInsertNewline = editContext.commonOps.insertPlainText('\n');
  return didInsertNewline ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

ExecutionInstruction splitBlockquoteWhenEnterPressed({
  required EditContext editContext,
  required RawKeyEvent keyEvent,
}) {
  if (keyEvent.logicalKey != LogicalKeyboardKey.enter) {
    return ExecutionInstruction.continueExecution;
  }

  if (editContext.composer.selection == null) {
    return ExecutionInstruction.continueExecution;
  }

  final baseNode = editContext.editor.document.getNodeById(editContext.composer.selection!.base.nodeId)!;
  final extentNode = editContext.editor.document.getNodeById(editContext.composer.selection!.extent.nodeId)!;
  if (baseNode.id != extentNode.id) {
    return ExecutionInstruction.continueExecution;
  }
  if (extentNode is! ParagraphNode) {
    return ExecutionInstruction.continueExecution;
  }
  if (extentNode.metadata['blockType'] != blockquoteAttribution) {
    return ExecutionInstruction.continueExecution;
  }

  final didSplit = editContext.commonOps.insertBlockLevelNewline();
  return didSplit ? ExecutionInstruction.haltExecution : ExecutionInstruction.continueExecution;
}

class SplitBlockquoteCommand implements EditorCommand {
  SplitBlockquoteCommand({
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
    final blockquote = node as ParagraphNode;
    final text = blockquote.text;
    final startText = text.copyText(0, splitPosition.offset);
    final endText = splitPosition.offset < text.text.length ? text.copyText(splitPosition.offset) : AttributedText();

    // Change the current node's content to just the text before the caret.
    // TODO: figure out how node changes should work in terms of
    //       a DocumentEditorTransaction (#67)
    blockquote.text = startText;

    // Create a new node that will follow the current node. Set its text
    // to the text that was removed from the current node.
    final isNewNodeABlockquote = endText.text.isNotEmpty;
    final newNode = ParagraphNode(
      id: newNodeId,
      text: endText,
      metadata: isNewNodeABlockquote ? {'blockType': blockquoteAttribution} : {},
    );

    // Insert the new node after the current node.
    transaction.insertNodeAfter(
      previousNode: node,
      newNode: newNode,
    );
  }
}

Widget? blockquoteBuilder(ComponentContext componentContext) {
  final blockquoteNode = componentContext.documentNode;
  if (blockquoteNode is! ParagraphNode) {
    return null;
  }
  if (blockquoteNode.metadata['blockType'] != blockquoteAttribution) {
    return null;
  }

  final textSelection = componentContext.nodeSelection?.nodeSelection as TextSelection?;
  final showCaret = componentContext.showCaret && (componentContext.nodeSelection?.isExtent ?? false);

  return BlockquoteComponent(
    textKey: componentContext.componentKey,
    text: blockquoteNode.text,
    styleBuilder: componentContext.extensions[textStylesExtensionKey],
    textSelection: textSelection,
    selectionColor: (componentContext.extensions[selectionStylesExtensionKey] as SelectionStyle).selectionColor,
    showCaret: showCaret,
    caretColor: (componentContext.extensions[selectionStylesExtensionKey] as SelectionStyle).textCaretColor,
  );
}
