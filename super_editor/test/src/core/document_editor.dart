import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/super_editor.dart';

void main() {
  group('MutableDocument', () {
    test('it replaces one node by another ', () {
      final oldNode = ParagraphNode(id: 'old', text: AttributedText());
      final document = MutableDocument(
        nodes: [
          HorizontalRuleNode(id: '0'),
          oldNode,
          HorizontalRuleNode(id: '2'),
        ],
      );

      final newNode = ParagraphNode(id: 'new', text: AttributedText());
      document.replaceNode(oldNode: oldNode, newNode: newNode);

      // oldNode does not exist
      expect(document.nodes.contains(oldNode), false);
      // newNode exists at index 1
      expect(document.nodes.indexOf(newNode), 1);
    });
  });
}
