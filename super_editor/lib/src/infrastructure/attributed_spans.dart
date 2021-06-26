import 'dart:math';

import 'package:collection/collection.dart';
import 'package:super_editor/src/infrastructure/_logging.dart';

final _log = Logger(scope: 'AttributedSpans');

/// A set of spans, each with an associated [Attribution], that take
/// up some amount of space in a discrete range.
///
/// [AttributedSpans] are useful when implementing attributed text
/// for the purpose of markup and styling.
///
/// You can think of [AttributedSpans] like a set of lanes. Each
/// lane may be occupied by some series of spans for a particular
/// attribute:
///
/// ------------------------------------------------------
/// Bold    :  {xxxx}                      {xxxxx}
/// Italics :             {xxxxxxxx}
/// Link    :                              {xxxxx}
/// ------------------------------------------------------
///
/// An attribution can be any subclass of [Attribution]. Based
/// on the type of [Attribution] that is used, two [Attributions]
/// might occupy the same lane or different lanes. For example,
/// any two [NamedAttribution]s occupy the same lane if-and-only-if
/// the two attributions have the same name, like "bold".
///
/// Each attributed span is represented by two `SpanMarker`s, one
/// with type `SpanMarkerType.start` and one with type
/// `SpanMarkerType.end`.
///
/// Spans with equivalent [Attribution]s cannot overlap each other, but
/// spans with different [Attribution]s can overlap each other.
///
/// When applying [AttributedSpans] to text as styles, you'll
/// eventually want a single collapsed list of spans. Use [collapseSpans()]
/// to collapse the different attribution spans into a single
/// series of multi-attribution spans.
class AttributedSpans {
  /// Constructs an [AttributedSpans] with the given [attributions].
  ///
  /// [attributions] may be omitted to create an [AttributedSpans]
  /// with no spans.
  AttributedSpans({
    List<SpanMarker>? attributions,
  }) : _attributions = [...?attributions] {
    _sortAttributions();
  }

  // _attributions must always be in order from lowest
  // marker offset to highest marker offset.
  final List<SpanMarker> _attributions;

  void _sortAttributions() {
    _attributions.sort((m1, m2) => m1.offset - m2.offset);
  }

  /// Returns true if this [AttributedSpans] contains at least one
  /// unit of attribution for each of the given [attributions]
  /// within the given range (inclusive).
  bool hasAttributionsWithin({
    required Set<Attribution> attributions,
    required int start,
    required int end,
  }) {
    final attributionsToFind = Set.from(attributions);
    for (int i = start; i <= end; ++i) {
      for (final attribution in attributionsToFind) {
        if (hasAttributionAt(i, attribution: attribution)) {
          attributionsToFind.remove(attribution);
        }

        if (attributionsToFind.isEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  Set<Attribution> getMatchingAttributionsWithin({
    required Set<Attribution> attributions,
    required int start,
    required int end,
  }) {
    final matchingAttributions = <Attribution>{};
    for (int i = start; i <= end; ++i) {
      for (final attribution in attributions) {
        final otherAttributions = getAllAttributionsAt(start);
        for (final otherAttribution in otherAttributions) {
          if (otherAttribution.id == attribution.id) {
            matchingAttributions.add(otherAttribution);
          }
        }
      }
    }
    return matchingAttributions;
  }

  /// Returns true if the given [offset] has the given [attribution].
  ///
  /// If the given [attribution] is null, returns [true] if any attribution
  /// exists at the given [offset].
  bool hasAttributionAt(
    int offset, {
    Attribution? attribution,
  }) {
    SpanMarker? markerBefore = _getStartingMarkerAtOrBefore(offset, attribution: attribution);
    if (markerBefore == null) {
      return false;
    }
    SpanMarker? markerAfter = _getEndingMarkerAtOrAfter(markerBefore.offset, attribution: attribution);
    if (markerAfter == null) {
      throw Exception('Found an open-ended attribution. It starts with: $markerBefore');
    }

    return (markerBefore.offset <= offset) && (offset <= markerAfter.offset);
  }

  AttributionSpan expandAttributionToSpan({
    required Attribution attribution,
    required int offset,
  }) {
    if (!hasAttributionAt(offset, attribution: attribution)) {
      throw Exception(
          'Tried to expand attribution ($attribution) at offset "$offset" but the given attribution does not exist at that offset.');
    }

    // The following methods should be guaranteed to produce non-null
    // values because we already verified that the given attribution
    // exists at the given offset.
    SpanMarker markerBefore = _getStartingMarkerAtOrBefore(offset, attribution: attribution)!;
    SpanMarker markerAfter = _getEndingMarkerAtOrAfter(markerBefore.offset, attribution: attribution)!;

    return AttributionSpan(
      attribution: attribution,
      start: markerBefore.offset,
      end: markerAfter.offset,
    );
  }

  /// Returns all attributions for spans that cover the given [offset].
  Set<Attribution> getAllAttributionsAt(int offset) {
    _log.log('getAllAttributionsAt', 'offset: $offset');
    _log.log('getAllAttributionsAt', ' - collecting all existing markers');
    final allAttributions = <Attribution>{};
    for (final marker in _attributions) {
      _log.log('getAllAttributionsAt', '   - marker: $marker');
      allAttributions.add(marker.attribution);
    }

    final attributionsAtOffset = <Attribution>{};
    for (final attribution in allAttributions) {
      final hasAttribution = hasAttributionAt(offset, attribution: attribution);
      if (hasAttribution) {
        _log.log('getAllAttributionsAt', ' - adding attribution: $attribution');
        attributionsAtOffset.add(attribution);
      }
    }

    return attributionsAtOffset;
  }

  /// Returns spans for each attribution that (at least partially) appear
  /// between [start] and [end], inclusive, as selected by [attributionFilter].
  ///
  /// By default, the returned spans represent the full, contiguous span
  /// of each attribution. This means that if a portion of an attribution
  /// appears between [start] and [end], the entire attribution span is
  /// returned, including the area that sits before [start] or after [end].
  ///
  /// To obtain attribution spans that are cut down and limited to the
  /// given [start]/[end] range, pass [true] for [resizeSpansToFitInRange].
  /// This setting only effects the returned spans, it does not alter the
  /// attributions within this [AttributedSpans].
  Set<AttributionSpan> getAttributionSpansInRange({
    required AttributionFilter attributionFilter,
    required int start,
    required int end,
    bool resizeSpansToFitInRange = false,
  }) {
    final matchingAttributionSpans = <AttributionSpan>{};

    // For every unit in the given range...
    for (int i = start; i <= end; ++i) {
      final attributionsAtOffset = getAllAttributionsAt(i);
      // For every attribution overlaps this unit...
      for (final attribution in attributionsAtOffset) {
        // If the caller wants this attribution...
        if (attributionFilter(attribution)) {
          // Calculate the span for this attribution.
          AttributionSpan span = expandAttributionToSpan(
            attribution: attribution,
            offset: i,
          );

          // If desired, resize the span to fit within the range.
          if (resizeSpansToFitInRange) {
            span = span.constrain(start: start, end: end);
          }

          // Add the span to the set. Duplicate are automatically ignored.
          matchingAttributionSpans.add(span);
        }
      }
    }

    return matchingAttributionSpans;
  }

  /// Finds and returns the nearest [start] marker that appears at or before the
  /// given [offset], optionally looking specifically for a marker with
  /// the given [attribution].
  SpanMarker? _getStartingMarkerAtOrBefore(int offset, {Attribution? attribution}) {
    return _attributions //
        .reversed // search from the end so its the nearest start marker
        .where((marker) {
      return attribution == null ||
          (marker.attribution.id == attribution.id && marker.attribution.canMergeWith(attribution));
    })
        // .where((marker) => attribution == null || marker.attribution.id == attribution.id)
        .firstWhereOrNull((marker) => marker.isStart && marker.offset <= offset);
  }

  /// Finds and returns the nearest [end] marker that appears at or after the
  /// given [offset], optionally looking specifically for a marker with
  /// the given [attribution].
  SpanMarker? _getEndingMarkerAtOrAfter(int offset, {Attribution? attribution}) {
    return _attributions
        .where((marker) =>
            attribution == null ||
            (marker.attribution.id == attribution.id && marker.attribution.canMergeWith(attribution)))
        .firstWhereOrNull((marker) => marker.isEnd && marker.offset >= offset);
  }

  /// Applies the [newAttribution] from [start] to [end], inclusive.
  ///
  /// If [newAttribution] spans already exist at [start] or [end], and those
  /// spans are compatible, the spans are expanded to include the new region
  /// between [start] and [end].
  ///
  /// It [newAttribution] overlaps a conflicting span, a
  /// [IncompatibleOverlappingAttributionsException] is thrown.
  void addAttribution({
    required Attribution newAttribution,
    required int start,
    required int end,
  }) {
    if (start < 0 || start > end) {
      return;
    }

    // Ensure that no conflicting attribution overlaps the new attribution.
    // If a conflict exists, throw an exception.
    final matchingAttributions = getMatchingAttributionsWithin(attributions: {newAttribution}, start: start, end: end);
    if (matchingAttributions.isNotEmpty) {
      for (final matchingAttribution in matchingAttributions) {
        if (!newAttribution.canMergeWith(matchingAttribution)) {
          late int conflictStart;
          for (int i = start; i <= end; ++i) {
            if (hasAttributionAt(i, attribution: matchingAttribution)) {
              conflictStart = i;
              break;
            }
          }

          throw IncompatibleOverlappingAttributionsException(
            existingAttribution: matchingAttribution,
            newAttribution: newAttribution,
            conflictStart: conflictStart,
          );
        }
      }
    }

    _log.log('addAttribution', 'start: $start -> end: $end');
    if (!hasAttributionAt(start, attribution: newAttribution)) {
      _log.log('addAttribution', 'adding start marker at: $start');
      _insertMarker(SpanMarker(
        attribution: newAttribution,
        offset: start,
        markerType: SpanMarkerType.start,
      ));
    }

    // Delete all matching attributions between `range.start`
    // and `range.end`.
    final markersToDelete = _attributions
        .where((attribution) => attribution.attribution == newAttribution)
        .where((attribution) => attribution.offset > start)
        .where((attribution) => attribution.offset <= end)
        .toList();
    _log.log('addAttribution', 'removing ${markersToDelete.length} markers between $start and $end');
    _attributions.removeWhere((element) => markersToDelete.contains(element));

    final lastDeletedMarker = markersToDelete.isNotEmpty ? markersToDelete.last : null;

    if (lastDeletedMarker == null || lastDeletedMarker.markerType == SpanMarkerType.end) {
      // If we didn't delete any markers, the span that began at
      // `range.start` or before needs to be capped off.
      //
      // If we deleted some markers, but the last marker was an
      // `end` marker, we still have an open-ended span and we
      // need to cap it off.
      _log.log('addAttribution', 'inserting ending marker at: $end');
      _insertMarker(SpanMarker(
        attribution: newAttribution,
        offset: end,
        markerType: SpanMarkerType.end,
      ));
    }
    // Else, `range.end` is in the middle of larger span and
    // doesn't need to be inserted.

    _log.log('addAttribution', 'all attributions after:');
    _attributions.where((element) => element.attribution == newAttribution).forEach((element) {
      _log.log('addAttribution', '$element');
    });
  }

  /// Removes [attributionToRemove] between [start] and [end], inclusive.
  void removeAttribution({
    required Attribution attributionToRemove,
    required int start,
    required int end,
  }) {
    if (start < 0 || start > end) {
      throw Exception('removeAttribution() did not satisfy start < 0 and start > end, start: $start, end: $end');
    }

    // It's possible that a span we want to remove was started before the
    // removal region and/or ended after the removal region. Therefore,
    // the first thing we do is cut off those outer spans one unit before
    // and/or after the removal region.
    //
    // Example:
    //    Starting spans + removal region:
    //    ---[xxxxx]---[yyyyyy]----
    //          |-remove-|
    //
    //    Spans after end cap adjustment:
    //    ---[xx]|xxx]---[yy|[yyy]----
    //
    //    Notice that the above marker structure is illegal.
    //    That's OK because the illegal configuration is only
    //    temporary. By the end of this method it will look
    //    like the following:
    //
    //    Spans after all inner markers are removed:
    //    ---[xx]--------[yyy]----
    final endCapMarkersToInsert = <SpanMarker>{};

    // Determine if we need to insert a new end-cap before
    // the removal region.
    if (hasAttributionAt(start, attribution: attributionToRemove)) {
      final markersAtStart = _getMarkerAt(attributionToRemove, start);
      if (markersAtStart.isEmpty) {
        endCapMarkersToInsert.add(SpanMarker(
          attribution: attributionToRemove,
          offset: start - 1,
          markerType: SpanMarkerType.end,
        ));
      }
    }

    // Determine if we need to insert a new end-cap after the
    // removal region.
    if (hasAttributionAt(end, attribution: attributionToRemove)) {
      final markersAtEnd = _getMarkerAt(attributionToRemove, end);
      if (markersAtEnd.isEmpty) {
        endCapMarkersToInsert.add(SpanMarker(
          attribution: attributionToRemove,
          offset: end + 1,
          markerType: SpanMarkerType.start,
        ));
      }
    }

    // Insert new span end-caps immediately before and after
    // the removal region, if needed.
    for (final endCapMarker in endCapMarkersToInsert) {
      _insertMarker(endCapMarker);
    }

    // Now that the end caps have been handled, remove all
    // relevant attribution markers between [start, end].
    final markersToDelete = _attributions
        .where((attribution) => attribution.attribution == attributionToRemove)
        .where((attribution) => attribution.offset >= start)
        .where((attribution) => attribution.offset <= end)
        .toList();
    _log.log('removeAttribution', 'removing ${markersToDelete.length} markers between $start and $end');
    _attributions.removeWhere((element) => markersToDelete.contains(element));

    _log.log('removeAttribution', 'all attributions after:');
    _attributions.where((element) => element.attribution == attributionToRemove).forEach((element) {
      _log.log('removeAttribution', ' - $element');
    });
  }

  /// If ALL of the units between [start] and [end], inclusive, contain the
  /// given [attribution], that attribution is removed from those units.
  /// Otherwise, all of the units between [start] and [end], inclusive,
  /// are assigned the [attribution].
  void toggleAttribution({
    required dynamic attribution,
    required int start,
    required int end,
  }) {
    if (_isContinuousAttribution(attribution: attribution, start: start, end: end)) {
      removeAttribution(attributionToRemove: attribution, start: start, end: end);
    } else {
      addAttribution(newAttribution: attribution, start: start, end: end);
    }
  }

  /// Returns [true] if the given [attribution] exists from [start] to
  /// [end], inclusive, without any breaks in between. Otherwise, returns
  /// [false].
  bool _isContinuousAttribution({
    required Attribution attribution,
    required int start,
    required int end,
  }) {
    _log.log('_isContinuousAttribution', 'attribution: "$attribution", range: $start -> $end');
    SpanMarker? markerBefore = _getNearestMarkerAtOrBefore(start, attribution: attribution);
    _log.log('_isContinuousAttribution', 'marker before: $markerBefore');

    if (markerBefore == null || markerBefore.isEnd) {
      return false;
    }

    final indexBefore = _attributions.indexOf(markerBefore);
    final nextMarker = _attributions.sublist(indexBefore).firstWhereOrNull(
          (marker) => marker.attribution == attribution && marker.offset > markerBefore.offset,
        );
    _log.log('_isContinuousAttribution', 'next marker: $nextMarker');

    if (nextMarker == null) {
      throw Exception('Inconsistent attributions state. Found a `start` marker with no matching `end`.');
    }
    if (nextMarker.isStart) {
      throw Exception('Inconsistent attributions state. Found a `start` marker following a `start` marker.');
    }

    // If there is even one additional marker in the `range`
    // of interest, it means that the given attribution is
    // not applied to the entire range.
    return nextMarker.offset >= end;
  }

  /// Finds and returns the nearest marker that appears at or after the
  /// given [offset], optionally looking specifically for a marker with
  /// the given [attribution].
  SpanMarker? _getNearestMarkerAtOrBefore(
    int offset, {
    Attribution? attribution,
  }) {
    SpanMarker? markerBefore;
    final markers =
        attribution != null ? _attributions.where((marker) => marker.attribution == attribution) : _attributions;

    for (final marker in markers) {
      if (marker.offset <= offset) {
        markerBefore = marker;
      }
      if (marker.offset > offset) {
        break;
      }
    }

    return markerBefore;
  }

  /// Returns the markers at the given [offset] with the given [attribution]..
  Set<SpanMarker> _getMarkerAt(Attribution attribution, int offset) {
    return _attributions
        .where((marker) => marker.attribution == attribution)
        .where((marker) => marker.offset == offset)
        .toSet();
  }

  /// Inserts the [newMarker] into this [AttributedSpans].
  ///
  /// Precondition: There must not already exist a marker with
  /// the same attribution at the same offset.
  void _insertMarker(SpanMarker newMarker) {
    SpanMarker? markerAfter =
        _attributions.firstWhereOrNull((existingMarker) => existingMarker.offset >= newMarker.offset);

    if (markerAfter != null) {
      final markerAfterIndex = _attributions.indexOf(markerAfter);
      _attributions.insert(markerAfterIndex, newMarker);
    } else {
      // Insert the new marker at the end.
      _attributions.add(newMarker);
    }
  }

  /// Pushes back all the spans in [other] to [index], and then appends
  /// the [other] spans to this [AttributedSpans].
  ///
  /// The [index] must be greater than the offset of the final marker
  /// within this [AttributedSpans].
  void addAt({
    required AttributedSpans other,
    required int index,
  }) {
    if (_attributions.isNotEmpty && _attributions.last.offset >= index) {
      throw Exception(
          'Another AttributedSpans can only be appended after the final marker in this AttributedSpans. Final marker: ${_attributions.last}');
    }

    _log.log('addAt', 'attributions before pushing them:');
    _log.log('addAt', toString());

    // Push back all the `other` markers to make room for the
    // spans we're putting in front of them.

    final pushDistance = index;
    _log.log('addAt', 'pushing `other` markers by: $pushDistance');
    _log.log('addAt', '`other` attributions before pushing them:');
    _log.log('addAt', other.toString());
    final pushedSpans = other.copy()..pushAttributionsBack(pushDistance);

    // Combine `this` and `other` attributions into one list.
    final List<SpanMarker> combinedAttributions = List.from(_attributions)..addAll(pushedSpans._attributions);
    _log.log('addAt', 'combined attributions before merge:');
    for (final marker in combinedAttributions) {
      _log.log('addAt', '   - $marker');
    }

    // Clean up the boundary between the two lists of attributions
    // by merging compatible attributions that meet at the boundary.
    _mergeBackToBackAttributions(combinedAttributions, index);

    _log.log('addAt', 'combined attributions after merge:');
    for (final marker in combinedAttributions) {
      _log.log('addAt', '   - $marker');
    }

    _attributions
      ..clear()
      ..addAll(combinedAttributions);
  }

  /// Given a list of [attributions], which includes two different lists of
  /// attributions concatenated together at [mergePoint], merges any
  /// attribution spans that exist back-to-back at the [mergePoint].
  void _mergeBackToBackAttributions(List<SpanMarker> attributions, int mergePoint) {
    _log.log('_mergeBackToBackAttributions', 'merging attributions at $mergePoint');
    // Look for any compatible attributions at
    // `mergePoint - 1` and `mergePoint` and combine them.
    final endAtMergePointMarkers =
        attributions.where((marker) => marker.isEnd && marker.offset == mergePoint - 1).toList();
    final startAtMergePointMarkers =
        attributions.where((marker) => marker.isStart && marker.offset == mergePoint).toList();
    for (final startMarker in startAtMergePointMarkers) {
      _log.log('_mergeBackToBackAttributions', 'marker on right side: $startMarker');
      final endMarker = endAtMergePointMarkers.firstWhereOrNull(
        (marker) => marker.attribution == startMarker.attribution,
      );
      _log.log('_mergeBackToBackAttributions', 'matching marker on left side? $endMarker');
      if (endMarker != null) {
        // These two attributions should be combined into one.
        // To do this, delete these two markers from the original
        // attribution list.
        _log.log('_mergeBackToBackAttributions', 'combining left/right spans at edge at index $mergePoint');
        _log.log('_mergeBackToBackAttributions', 'Removing markers:');
        _log.log('_mergeBackToBackAttributions', ' - $startMarker');
        _log.log('_mergeBackToBackAttributions', ' - $endMarker');
        attributions..remove(startMarker)..remove(endMarker);
      }
    }
  }

  /// Returns of a copy of this [AttributedSpans] between [startOffset]
  /// and [endOffset].
  ///
  /// If no [endOffset] is provided, a copy is made from [startOffset]
  /// to the [offset] of the last marker in this [AttributedSpans].
  AttributedSpans copyAttributionRegion(int startOffset, [int? endOffset]) {
    endOffset = endOffset ?? _attributions.lastOrNull?.offset ?? 0;
    _log.log('copyAttributionRegion', 'start: $startOffset, end: $endOffset');

    final List<SpanMarker> cutAttributions = [];

    _log.log('copyAttributionRegion', 'inspecting existing markers in full AttributedSpans');
    final Map<Attribution, int> foundStartMarkers = {};
    final Map<Attribution, int> foundEndMarkers = {};

    // Analyze all markers that appear before the start of
    // the copy range so that we can insert any appropriate
    // `start` markers at the beginning of the copy range.
    _attributions //
        .where((marker) => marker.offset < startOffset) //
        .forEach((marker) {
      _log.log('copyAttributionRegion', 'marker before the copy region: $marker');
      // Track any markers that begin before the `startOffset`
      // and continue beyond `startOffset`.
      if (marker.isStart) {
        _log.log('copyAttributionRegion', 'remembering this marker to insert in copied region');
        foundStartMarkers.putIfAbsent(marker.attribution, () => 0);
        foundStartMarkers[marker.attribution] = foundStartMarkers[marker.attribution]! + 1;
      } else {
        _log.log('copyAttributionRegion',
            'this marker counters an earlier one we found. We will not re-insert this marker in the copied region');
        foundStartMarkers.putIfAbsent(marker.attribution, () => 0);
        foundStartMarkers[marker.attribution] = foundStartMarkers[marker.attribution]! - 1;
      }
    });

    // Insert any `start` markers at the start of the copy region
    // so that we maintain attribution symmetry.
    foundStartMarkers.forEach((markerAttribution, count) {
      if (count == 1) {
        // Found an unmatched `start` marker. Replace it.
        _log.log('copyAttributionRegion',
            'inserting "$markerAttribution" marker at start of copy region to maintain symmetry.');
        cutAttributions.add(SpanMarker(
          attribution: markerAttribution,
          offset: 0,
          markerType: SpanMarkerType.start,
        ));
      } else if (count < 0 || count > 1) {
        throw Exception(
            'Found an unbalanced number of `start` and `end` markers before offset: $startOffset - $_attributions');
      }
    });

    // Directly copy every marker that appears within the cut
    // region.
    _attributions //
        .where((marker) => startOffset <= marker.offset && marker.offset <= endOffset!) //
        .forEach((marker) {
      _log.log('copyAttributionRegion',
          'copying "${marker.attribution}" at ${marker.offset} from original AttributionSpans to copy region.');
      cutAttributions.add(marker.copyWith(
        offset: marker.offset - startOffset,
      ));
    });

    // Analyze all markers that appear after the end of
    // the copy range so that we can insert any appropriate
    // `end` markers at the end of the copy range.
    _attributions //
        .reversed //
        .where((marker) => marker.offset > endOffset!) //
        .forEach((marker) {
      _log.log('copyAttributionRegion', 'marker after the copy region: $marker');
      // Track any markers that end after the `endOffset`
      // and start before `endOffset`.
      if (marker.isEnd) {
        _log.log('copyAttributionRegion', 'remembering this marker to insert in copied region');
        foundEndMarkers.putIfAbsent(marker.attribution, () => 0);
        foundEndMarkers[marker.attribution] = foundEndMarkers[marker.attribution]! + 1;
      } else {
        _log.log('copyAttributionRegion',
            'this marker counters an earlier one we found. We will not re-insert this marker in the copied region');
        foundEndMarkers.putIfAbsent(marker.attribution, () => 0);
        foundEndMarkers[marker.attribution] = foundEndMarkers[marker.attribution]! - 1;
      }
    });

    // Insert any `end` markers at the end of the copy region
    // so that we maintain attribution symmetry.
    foundEndMarkers.forEach((markerAttribution, count) {
      if (count == 1) {
        // Found an unmatched `end` marker. Replace it.
        _log.log('copyAttributionRegion',
            'inserting "$markerAttribution" marker at end of copy region to maintain symmetry.');
        cutAttributions.add(SpanMarker(
          attribution: markerAttribution,
          offset: endOffset! - startOffset,
          markerType: SpanMarkerType.end,
        ));
      } else if (count < 0 || count > 1) {
        throw Exception(
            'Found an unbalanced number of `start` and `end` markers after offset: $endOffset - $_attributions');
      }
    });

    _log.log('copyAttributionRegion', 'copied attributions:');
    for (final attribution in cutAttributions) {
      _log.log('copyAttributionRegion', '   - $attribution');
    }

    return AttributedSpans(attributions: cutAttributions);
  }

  /// Changes all spans in this [AttributedSpans] by pushing
  /// them back by [offset] amount.
  void pushAttributionsBack(int offset) {
    final pushedAttributions = _attributions.map((marker) => marker.copyWith(offset: marker.offset + offset)).toList();
    _attributions
      ..clear()
      ..addAll(pushedAttributions);
  }

  /// Changes spans in this [AttributedSpans] by cutting out the
  /// region from [startOffset] to [startOffset + count], exclusive.
  void contractAttributions({
    required int startOffset,
    required int count,
  }) {
    final contractedAttributions = <SpanMarker>[];

    // Add all the markers that are unchanged.
    contractedAttributions.addAll(_attributions.where((marker) => marker.offset < startOffset));

    _log.log('contractAttributions', 'removing $count characters starting at $startOffset');
    final needToEndAttributions = <dynamic>{};
    final needToStartAttributions = <dynamic>{};
    _attributions
        .where((marker) => (startOffset <= marker.offset) && (marker.offset < startOffset + count))
        .forEach((marker) {
      // Get rid of this marker and keep track of
      // any open-ended attributions that need to
      // be closed.
      _log.log('contractAttributions', 'removing ${marker.markerType} at ${marker.offset}');
      if (marker.isStart) {
        if (needToEndAttributions.contains(marker.attribution)) {
          // We've already removed an `end` marker so now
          // we're even.
          needToEndAttributions.remove(marker.attribution);
        } else {
          // We've removed a `start` marker that needs to
          // be replaced down the line.
          needToStartAttributions.add(marker.attribution);
        }
      } else {
        if (needToStartAttributions.contains(marker.attribution)) {
          // We've already removed a `start` marker so now
          // we're even.
          needToStartAttributions.remove(marker.attribution);
        } else {
          // We've removed an `end` marker that needs to
          // be replaced down the line.
          needToEndAttributions.add(marker.attribution);
        }
      }
    });

    // Re-insert any markers that are needed to retain
    // symmetry after the deletions above.
    for (final attribution in needToStartAttributions) {
      final offset = startOffset > 0 ? startOffset - 1 : 0;
      _log.log('contractAttributions', 'adding back a start marker at $offset');
      contractedAttributions.add(SpanMarker(
        attribution: attribution,
        offset: offset,
        markerType: SpanMarkerType.start,
      ));
    }
    for (final attribution in needToEndAttributions) {
      final offset = startOffset > 0 ? startOffset - 1 : 0;
      _log.log('contractAttributions', 'adding back an end marker at $offset');
      contractedAttributions.add(SpanMarker(
        attribution: attribution,
        offset: offset,
        markerType: SpanMarkerType.end,
      ));
    }

    // Add all remaining markers but with an `offset`
    // that is less by `count`.
    contractedAttributions.addAll(
      _attributions
          .where((marker) => marker.offset >= startOffset + count)
          .map((marker) => marker.copyWith(offset: marker.offset - count)),
    );

    _attributions
      ..clear()
      ..addAll(contractedAttributions);
  }

  /// Returns a copy of this [AttributedSpans].
  AttributedSpans copy() {
    return AttributedSpans(
      attributions: List.from(_attributions),
    );
  }

  /// Combines all spans of different types into a single
  /// list of spans that contain multiple types per segment.
  ///
  /// The returned spans are ordered from beginning to end.
  List<MultiAttributionSpan> collapseSpans({
    required int contentLength,
  }) {
    _log.log('collapseSpans', 'content length: $contentLength');
    _log.log('collapseSpans', 'attributions used to compute spans:');
    for (final marker in _attributions) {
      _log.log('collapseSpans', '   - $marker');
    }

    if (contentLength == 0) {
      // There is no content and therefore no attributions.
      _log.log('collapseSpans', 'content is empty. Returning empty span list.');
      return [];
    }

    // Cut up attributions in a series of corresponding "start"
    // and "end" points for every different combination of
    // attributions.
    final startPoints = <int>[0]; // we always start at zero
    final endPoints = <int>[];

    _log.log('collapseSpans', 'accumulating start and end points:');
    for (final marker in _attributions) {
      _log.log('collapseSpans', 'marker at ${marker.offset}');
      _log.log('collapseSpans', 'start points before change: $startPoints');
      _log.log('collapseSpans', 'end points before change: $endPoints');

      if (marker.offset > contentLength - 1) {
        _log.log('collapseSpans', 'this marker is beyond the desired content length. Breaking loop.');
        break;
      }

      if (marker.isStart) {
        // Add a `start` point.
        if (!startPoints.contains(marker.offset)) {
          _log.log('collapseSpans', 'adding start point at ${marker.offset}');
          startPoints.add(marker.offset);
        }

        // If there are no attributions before this `start` point
        // then there won't be an `end` just before this
        // `start` point. Insert one.
        if (marker.offset > 0 && !endPoints.contains(marker.offset - 1)) {
          _log.log('collapseSpans', 'going back one and adding end point at: ${marker.offset - 1}');
          endPoints.add(marker.offset - 1);
        }
      }
      if (marker.isEnd) {
        // Add an `end` point.
        if (!endPoints.contains(marker.offset)) {
          _log.log('collapseSpans', 'adding an end point at: ${marker.offset}');
          endPoints.add(marker.offset);
        }

        // Automatically start another range if we aren't at
        // the end of the content. We do this because we're not
        // guaranteed to have another `start` marker after this
        // `end` marker.
        if (marker.offset < contentLength - 1 && !startPoints.contains(marker.offset + 1)) {
          _log.log('collapseSpans', 'jumping forward one to add a start point at: ${marker.offset + 1}');
          startPoints.add(marker.offset + 1);
        }
      }

      _log.log('collapseSpans', 'start points after change: $startPoints');
      _log.log('collapseSpans', 'end points after change: $endPoints');
    }
    if (!endPoints.contains(contentLength - 1)) {
      // This condition occurs when there are no attributions.
      _log.log('collapseSpans', 'adding a final endpoint at end of text');
      endPoints.add(contentLength - 1);
    }

    if (startPoints.length != endPoints.length) {
      _log.log('collapseSpans', 'start points: $startPoints');
      _log.log('collapseSpans', 'end points: $endPoints');
      throw Exception(
          ' - mismatch between number of start points and end points. Content length: $contentLength, Start: ${startPoints.length} -> $startPoints, End: ${endPoints.length} -> $endPoints, from attributions: $_attributions');
    }

    // Sort the start and end points so that they can be
    // processed from beginning to end.
    startPoints.sort();
    endPoints.sort();

    // Create the collapsed spans.
    List<MultiAttributionSpan> collapsedSpans = [];
    for (int i = 0; i < startPoints.length; ++i) {
      _log.log('collapseSpans', 'building span from ${startPoints[i]} -> ${endPoints[i]}');
      _log.log('collapseSpans', ' - attributions in span: ${getAllAttributionsAt(startPoints[i])}');
      final attributionsAtOffset = getAllAttributionsAt(startPoints[i]);

      collapsedSpans.add(MultiAttributionSpan(
        start: startPoints[i],
        end: endPoints[i],
        attributions: attributionsAtOffset,
      ));
    }
    _log.log('collapseSpans', 'returning collapsed spans: $collapsedSpans');
    return collapsedSpans;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttributedSpans &&
          runtimeType == other.runtimeType &&
          const DeepCollectionEquality().equals(_attributions, other._attributions);

  @override
  int get hashCode => _attributions.hashCode;

  @override
  String toString() {
    final buffer = StringBuffer('[AttributedSpans] (${(_attributions.length / 2).round()} spans):');
    for (final marker in _attributions) {
      buffer.write('\n - $marker');
    }
    return buffer.toString();
  }
}

/// Marks the start or end of an attribution span.
///
/// The given [AttributionType] must implement equality for
/// span management to work correctly.
class SpanMarker implements Comparable<SpanMarker> {
  /// Constructs a [SpanMarker] with the given [attribution], [offset] within
  /// some discrete content, and [markerType] of [start] or [end].
  const SpanMarker({
    required this.attribution,
    required this.offset,
    required this.markerType,
  });

  /// The attribution that exists between this [SpanMarker] and its
  /// other endpoint.
  final Attribution attribution;

  /// The position of this [SpanMarker] within some discrete content.
  final int offset;

  /// The type of [SpanMarker], either [start] or [end].
  final SpanMarkerType markerType;

  /// Returns true if this marker is a [SpanMarkerType.start] marker.
  bool get isStart => markerType == SpanMarkerType.start;

  /// Returns true if this marker is a [SpanMarkerType.end] marker.
  bool get isEnd => markerType == SpanMarkerType.end;

  /// Returns a copy of this [SpanMarker] with optional new values
  /// for [attribution], [offset], and [markerType].
  SpanMarker copyWith({
    Attribution? attribution,
    int? offset,
    SpanMarkerType? markerType,
  }) =>
      SpanMarker(
        attribution: attribution ?? this.attribution,
        offset: offset ?? this.offset,
        markerType: markerType ?? this.markerType,
      );

  @override
  String toString() => '[SpanMarker] - attribution: $attribution, offset: $offset, type: $markerType';

  @override
  int compareTo(SpanMarker other) {
    return offset - other.offset;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpanMarker &&
          attribution == other.attribution &&
          offset == other.offset &&
          markerType == other.markerType;

  @override
  int get hashCode => attribution.hashCode ^ offset.hashCode ^ markerType.hashCode;
}

/// The type of a marker within a span, either [start] or [end].
enum SpanMarkerType {
  start,
  end,
}

/// An [Attribution] span from [start] to [end], inclusive.
class AttributionSpan {
  const AttributionSpan({
    required this.attribution,
    required this.start,
    required this.end,
  });

  final Attribution attribution;
  final int start;
  final int end;

  AttributionSpan constrain({
    required int start,
    required int end,
  }) {
    return copyWith(
      start: max(this.start, start),
      end: min(this.end, end),
    );
  }

  AttributionSpan copyWith({
    Attribution? attribution,
    int? start,
    int? end,
  }) {
    return AttributionSpan(
      attribution: attribution ?? this.attribution,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  @override
  String toString() {
    return '[AttributionSpan] - $attribution, $start -> $end';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttributionSpan &&
          runtimeType == other.runtimeType &&
          attribution == other.attribution &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => attribution.hashCode ^ start.hashCode ^ end.hashCode;
}

/// A span that contains zero or more attributions.
///
/// An [AttributedSpans] can be collapsed to a single list
/// of [MultiAttributionSpan]s with [AttributedSpans.collapseSpans].
class MultiAttributionSpan {
  const MultiAttributionSpan({
    required this.attributions,
    required this.start,
    required this.end,
  });

  final Set<Attribution> attributions;
  final int start;
  final int end;
}

typedef AttributionFilter = bool Function(Attribution candidate);

/// An attribution that can be associated with a span within
/// an [AttributedSpan].
///
/// To attribute a span with a name, consider using a
/// [NamedAttribution].
abstract class Attribution {
  /// Attributions with different IDs can overlap each
  /// other, but attributions with the same ID cannot
  /// overlap.
  ///
  /// For example, consider the use of attributions within
  /// [AttributedText]. One attribution might have an ID
  /// of "bold" and another might have an of "italics". Those
  /// attributions can overlap at the same location. However,
  /// two attributions both with the ID of "bold" cannot overlap.
  /// The matching attributions can only be combined into a new,
  /// larger attributed span.
  String get id;

  /// Returns [true] if this [Attribution] can be combined with
  /// the [other] [Attribution], replacing both smaller attributions
  /// with one larger attribution.
  bool canMergeWith(Attribution other);
}

/// [Attribution] that is defined by a given [String].
///
/// Any two [NamedAttribution]s with the same [id]/[name] are
/// considered equivalent and merge-able.
class NamedAttribution implements Attribution {
  const NamedAttribution(this.id);

  @override
  final String id;

  String get name => id;

  @override
  bool canMergeWith(Attribution other) {
    return this == other;
  }

  @override
  String toString() {
    return '[NamedAttribution]: $name';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NamedAttribution && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class IncompatibleOverlappingAttributionsException implements Exception {
  IncompatibleOverlappingAttributionsException({
    required this.existingAttribution,
    required this.newAttribution,
    required this.conflictStart,
  });

  final Attribution existingAttribution;
  final Attribution newAttribution;
  final int conflictStart;

  @override
  String toString() {
    return 'Tried to insert attribution ($newAttribution) over a conflicting existing attribution ($existingAttribution). The overlap began at index $conflictStart';
  }
}
