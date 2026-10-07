import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class Note {
  Note({
    required this.title,
    required this.color,
    this.body,
    this.items = const [],
    this.checkedExtra = 0,
    this.tags = const [],
  });

  final String title;
  final Color color;
  final String? body;
  final List<String> items;
  final int checkedExtra;
  final List<String> tags;
}

final _notes = <Note>[
  Note(
    title: 'Useful hints to build a\nperfect design for iPhone Xs',
    color: const Color(0xFFF2ED9F),
    body:
        'Apple presents new gadgets every year, and each of this device deserves '
        'the attention. But when iPhone X was presented to the public, rules of '
        'app designing were changed. With iPhone Xs announcement this year, UI/UX '
        'designers',
    tags: const ['Design'],
  ),
  Note(
    title: 'Europe travel packing list',
    color: const Color(0xFFDCE7A0),
    items: const [
      'Suitcase/travel backpack',
      '3-4 t-shirts',
      'Sweater',
      'Lightweight jacket',
      'Pair of dark wash jeans',
      'Theft-proof backpack',
      'Plug converters',
      'Passport and ID',
    ],
    tags: const ['Travel'],
  ),
  Note(
    title: 'Weekend checklist',
    color: const Color(0xFFADDCD8),
    items: const [
      'Call mom and dad',
      'Prep the meals for the week',
      'Tidy up living spaces',
      'Plan the week + month ahead',
    ],
    checkedExtra: 5,
    tags: const ['Things to do', 'May 3 2020, 20:00'],
  ),
  Note(
    title: '10 Reasons You Should Wake-Up\nAt 5AM For 30 Days Straight',
    color: const Color(0xFFF2C6D8),
    body: "For the remainder of this article, I'm going to make you specific "
        'promises about what will happen if you do this.\n'
        'To be absolutely clear: If you wake up at 5AM for 30 days straight, '
        'your entire life will change',
  ),
  Note(
    title: 'Understanding Business Value',
    color: const Color(0xFFDCCDEB),
    body: 'A designer that understands how to continually bring value to the '
        'business while also advocating for the user is a golden egg for '
        'organizations.',
    tags: const ['Article'],
  ),
  Note(
    title: 'Grocery Shopping',
    color: const Color(0xFFF5D5BC),
    items: const [
      'Peanut Butter',
      '16 oz Cottage Cheese',
      '6.5 lbs Chicken Breast',
      'Granny Smith Apples',
    ],
    tags: const ['Shopping'],
  ),
];

// iOS dark system greys.
const _bg = Color(0xFF1C1C1E);
const _surface = Color(0xFF2C2C2E);

/// Size of the resting dog-ear. It is just a very small fold.
const dogEar = 26.0;

/// How close to the top-right corner a long-press must land to grab the ear.
const _grabRadius = 80.0;

// ─────────────────────────────────────────────────────────────────────────────
// Paper fold
//
// You grab the top-right corner C and drag it to F. A real sheet creases along
// the perpendicular bisector of C→F: everything on C's side is the flap, and
// the flap is exactly that region mirrored across the crease.
//
// At rest, F sits at C + (-dogEar, +dogEar) — which produces precisely the
// little folded corner. Same maths, no special case.
// ─────────────────────────────────────────────────────────────────────────────

Offset foldCorner(Size size) => Offset(size.width, 0);

Offset restFinger(Size size) =>
    foldCorner(size) + const Offset(-dogEar, dogEar);

/// Reflection of [p] across the line through [mid] with unit normal [n].
Offset reflectPoint(Offset p, Offset mid, Offset n) {
  final d = p - mid;
  return p - n * (2 * (d.dx * n.dx + d.dy * n.dy));
}

Matrix4 _reflectionMatrix(Offset mid, Offset n) {
  final dot = mid.dx * n.dx + mid.dy * n.dy;
  return Matrix4.zero()
    ..setEntry(0, 0, 1 - 2 * n.dx * n.dx)
    ..setEntry(0, 1, -2 * n.dx * n.dy)
    ..setEntry(1, 0, -2 * n.dx * n.dy)
    ..setEntry(1, 1, 1 - 2 * n.dy * n.dy)
    ..setEntry(2, 2, 1)
    ..setEntry(3, 3, 1)
    ..setEntry(0, 3, 2 * dot * n.dx)
    ..setEntry(1, 3, 2 * dot * n.dy);
}

/// Half-plane `(p - mid)·n <= 0`, as a polygon big enough to cover [extent].
Path _halfPlane(Offset mid, Offset n, double extent) {
  final along = Offset(-n.dy, n.dx) * extent;
  final back = n * -extent;
  final a = mid + along, b = mid - along;
  return Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(b.dx + back.dx, b.dy + back.dy)
    ..lineTo(a.dx + back.dx, a.dy + back.dy)
    ..close();
}

class _Crease {
  const _Crease(this.mid, this.n);
  final Offset mid;
  final Offset n;
}

/// null when there is nothing to fold.
_Crease? _creaseFor(Size size, Offset? finger) {
  final corner = foldCorner(size);
  final f = finger ?? restFinger(size);
  final v = f - corner;
  return v.distance < 0.5 ? null : _Crease((corner + f) / 2, v / v.distance);
}

Path _cardPath(Size size) => Path()
  ..addRRect(
    RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
  );

class _KeepClipper extends CustomClipper<Path> {
  const _KeepClipper(this.finger);

  final Offset? finger;

  @override
  Path getClip(Size size) {
    final crease = _creaseFor(size, finger);
    if (crease == null) return _cardPath(size);
    // keep the side the corner is NOT on → normal points away from the corner
    return Path.combine(
      PathOperation.intersect,
      _cardPath(size),
      _halfPlane(crease.mid, -crease.n, size.longestSide * 3),
    );
  }

  @override
  bool shouldReclip(_KeepClipper old) => old.finger != finger;
}

class _FlapPainter extends CustomPainter {
  const _FlapPainter(this.finger, this.color);

  final Offset? finger;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final crease = _creaseFor(size, finger);
    if (crease == null) return;

    final folded = Path.combine(
      PathOperation.intersect,
      _cardPath(size),
      _halfPlane(crease.mid, crease.n, size.longestSide * 3),
    );
    if (folded.getBounds().isEmpty) return;

    final flap =
        folded.transform(_reflectionMatrix(crease.mid, crease.n).storage);
    final reach = flap.getBounds().longestSide;

    canvas.drawShadow(
        flap, CupertinoColors.black, (reach / 12).clamp(1.0, 10.0), false);

    // back of the sheet: darker, and darkest right along the crease
    canvas.drawPath(
      flap,
      Paint()
        ..shader = ui.Gradient.linear(
          crease.mid,
          crease.mid - crease.n * reach,
          [
            Color.lerp(color, CupertinoColors.black, .40)!,
            Color.lerp(color, CupertinoColors.black, .14)!,
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_FlapPainter old) =>
      old.finger != finger || old.color != color;
}

/// A note that folds like paper. [finger] is where the top-right corner is
/// being dragged to, in the widget's own coordinates; null means "at rest",
/// which still shows the dog-ear.
class NoteCard extends StatelessWidget {
  const NoteCard({super.key, required this.note, this.finger});

  final Note note;
  final Offset? finger;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipPath(
          clipper: _KeepClipper(finger),
          child: _NoteContent(note: note),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _FlapPainter(finger, note.color)),
          ),
        ),
      ],
    );
  }
}

class _NoteContent extends StatelessWidget {
  const _NoteContent({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF2B2B2B);
    return Container(
      width: double.infinity,
      color: note.color,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // leave room for the dog-ear so the title never runs under it
            padding: const EdgeInsets.only(right: dogEar),
            child: Text(
              note.title,
              style: const TextStyle(
                color: ink,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (note.body != null) ...[
            const SizedBox(height: 8),
            Text(
              note.body!,
              style: const TextStyle(color: ink, fontSize: 11, height: 1.45),
            ),
          ],
          if (note.items.isNotEmpty) const SizedBox(height: 8),
          for (final item in note.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: ink.withValues(alpha: .55), width: 1.2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item,
                        style: const TextStyle(color: ink, fontSize: 11)),
                  ),
                ],
              ),
            ),
          if (note.checkedExtra > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '+${note.checkedExtra} checked items',
                style:
                    TextStyle(color: ink.withValues(alpha: .6), fontSize: 10),
              ),
            ),
          if (note.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              children: [
                for (final tag in note.tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: CupertinoColors.white.withValues(alpha: .55),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(tag,
                        style: const TextStyle(color: ink, fontSize: 9)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions
// ─────────────────────────────────────────────────────────────────────────────

enum NoteAction {
  delete('Delete', CupertinoIcons.delete),
  archive('Archive', CupertinoIcons.archivebox),
  share('Share', CupertinoIcons.share);

  const NoteAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _actionGap = 24.0; // between the note and the action row
const _actionSize = 44.0;
const _hitRadius = 60.0;

/// Centre of each action button, in the note's own coordinate space.
Offset actionCenter(Size noteSize, int index) => Offset(
      noteSize.width * (index + .5) / NoteAction.values.length,
      noteSize.height + _actionGap + _actionSize / 2,
    );

NoteAction? actionUnder(Offset finger, Size noteSize) {
  NoteAction? best;
  var bestDistance = _hitRadius;
  for (final (i, a) in NoteAction.values.indexed) {
    final d = (actionCenter(noteSize, i) - finger).distance;
    if (d < bestDistance) {
      bestDistance = d;
      best = a;
    }
  }
  return best;
}

/// Fades and lifts a button into place. [t] runs 0 → 1 (and may overshoot).
class _Enter extends StatelessWidget {
  const _Enter({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 24 * (1 - t)),
        child: child,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.active, this.onTap});

  final NoteAction action;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: active ? 1.15 : 1,
            duration: const Duration(milliseconds: 150),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _actionSize,
              height: _actionSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? CupertinoColors.systemBlue : _surface,
              ),
              child: Icon(action.icon, size: 20, color: CupertinoColors.white),
            ),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Text(
            action.label,
            style: const TextStyle(color: CupertinoColors.white, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List screen
//
// The overlay is an OverlayEntry, not a route, so the long-press that opened it
// keeps feeding it move updates — grab the ear and fold in one uninterrupted
// gesture, no need to lift a finger.
// ─────────────────────────────────────────────────────────────────────────────

class StickyNotesView extends StatefulWidget {
  const StickyNotesView({super.key});

  @override
  State<StickyNotesView> createState() => _StickyNotesViewState();
}

class _StickyNotesViewState extends State<StickyNotesView>
    with TickerProviderStateMixin {
  late final List<Note> notes = List.of(_notes);
  final _keys = <Note, GlobalKey>{};

  /// Drives the fold when the finger lets go.
  late final AnimationController _anim;

  /// Drives the overlay coming in and going out.
  late final AnimationController _intro;

  // Built here rather than in `late final` initialisers: those are lazy, so a
  // screen disposed without ever folding a note would run them from dispose(),
  // where `vsync: this` looks up an ancestor of a deactivated widget and throws.
  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        _finger.value =
            Offset.lerp(_from, _to, Curves.easeOut.transform(_anim.value));
      });
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    );
    // Closing the gap left by a removed note. 580ms / easeInOutCubic, measured
    // off the reference: the notes below slide up exactly one slot.
    _collapse = AnimationController(
      vsync: this,
      value: 1,
      duration: const Duration(milliseconds: 580),
    );
  }

  /// Collapses the slot of the note being removed. Null when nothing is going.
  late final AnimationController _collapse;
  Note? _collapsing;

  final _finger = ValueNotifier<Offset?>(null);
  OverlayEntry? _entry;
  Note? _active;
  Rect _rect = Rect.zero;
  bool _grabbed = false;
  bool _menuMode = false;

  @override
  void dispose() {
    _entry?.remove();
    _toastEntry?.remove();
    _toastTimer?.cancel();
    _collapse.dispose();
    _anim.dispose();
    _intro.dispose();
    _finger.dispose();
    super.dispose();
  }

  Size get _noteSize => _rect.size;

  void _pressStart(Note note, Offset local) {
    final box = _keys[note]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || _entry != null) return;

    _anim.stop();
    _active = note;
    _rect = box.localToGlobal(Offset.zero) & box.size;
    _finger.value = null;
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_entry!);
    _intro.forward(from: 0);

    // pressing on the dog-ear starts the fold straight away, same gesture
    _grab(local);
    // opened from the body, not the ear: the menu stays put between folds
    _menuMode = !_grabbed;
  }

  /// Engage the fold if [local] landed on the dog-ear.
  void _grab(Offset local) {
    _anim.stop();
    _grabbed = (local - foldCorner(_noteSize)).distance < _grabRadius;
    if (_grabbed) _finger.value = local;
  }

  void _pressMove(Offset local) {
    if (_grabbed) _finger.value = local;
  }

  void _pressEnd() {
    if (!_grabbed) return; // no fold started → the menu just stays open
    final finger = _finger.value;
    final action = finger == null ? null : actionUnder(finger, _noteSize);
    if (action == null) {
      // unfold. Opened from the ear → that gesture is over, dismiss.
      // Opened from the body → the menu was the point, keep it up.
      _animateTo(restFinger(_noteSize),
          then: _menuMode ? _releaseFold : _close);
    } else {
      // drive the crease well past the opposite corner so the sheet folds shut
      final corner = foldCorner(_noteSize);
      final opposite = Offset(0, _noteSize.height);
      _animateTo(corner + (opposite - corner) * 2.2,
          then: () => _close(action));
    }
  }

  void _animateTo(Offset target, {required VoidCallback then}) {
    _from = _finger.value ?? restFinger(_noteSize);
    _to = target;
    _anim
      ..value = 0
      ..forward().then((_) => then());
  }

  Offset _from = Offset.zero, _to = Offset.zero;

  /// Fold released without picking an action, menu stays open.
  void _releaseFold() {
    _grabbed = false;
    _finger.value = null;
  }

  void _close([NoteAction? action]) {
    if (_entry == null || _intro.status == AnimationStatus.reverse) return;
    final note = _active;
    _grabbed = false;

    if (action != null && note != null) {
      // The reference closes the gap *while* the scrim is still fading, so the
      // dismissal is slowed to overlap it rather than finishing first.
      _intro.reverseDuration = const Duration(milliseconds: 420);
      setState(() => _collapsing = note);
      _collapse
        ..value = 1
        ..reverse().then((_) {
          if (!mounted) return;
          setState(() {
            notes.remove(note);
            _keys.remove(note);
            _collapsing = null;
          });
        });
      _toast('${action.label}: ${note.title.split('\n').first}');
    } else {
      _intro.reverseDuration = const Duration(milliseconds: 180);
    }

    _intro.reverse().then((_) {
      _entry?.remove();
      _entry = null;
      _active = null;
      _finger.value = null;
    });
  }

  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  /// iOS has no snackbar. This is the small transient capsule the system HUD
  /// uses, which removes itself.
  void _toast(String message) {
    _toastEntry?.remove();
    _toastTimer?.cancel();
    final entry = OverlayEntry(
      builder: (context) => Positioned(
        left: 0,
        right: 0,
        bottom: MediaQuery.of(context).padding.bottom + 40,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (context, t, child) => Opacity(opacity: t, child: child),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                child: Text(
                  message,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    Overlay.of(context).insert(entry);
    _toastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (_toastEntry != entry) return;
      entry.remove();
      _toastEntry = null;
    });
  }

  Widget _buildOverlay(BuildContext context) {
    final note = _active!;
    return ValueListenableBuilder<Offset?>(
      valueListenable: _finger,
      builder: (context, finger, _) {
        final hovered = finger == null ? null : actionUnder(finger, _noteSize);
        // An Overlay sits outside the app's DefaultTextStyle, so give it one
        // explicitly, else Text renders with the debug yellow underline.
        return DefaultTextStyle(
          style: CupertinoTheme.of(context).textTheme.textStyle,
          child: AnimatedBuilder(
            animation: _intro,
            builder: (context, _) => Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: Container(
                      color: CupertinoColors.black
                          .withValues(alpha: .72 * _intro.value),
                    ),
                  ),
                ),
                Positioned(
                  left: _rect.left,
                  top: _rect.top,
                  width: _rect.width,
                  height: _rect.height,
                  // lets you grab the ear once the menu is already open
                  child: GestureDetector(
                    onPanStart: (d) => _grab(d.localPosition),
                    onPanUpdate: (d) => _pressMove(d.localPosition),
                    onPanEnd: (_) => _pressEnd(),
                    onPanCancel: _pressEnd,
                    child: NoteCard(note: note, finger: finger),
                  ),
                ),
                Positioned(
                  left: _rect.left,
                  top: _rect.top + _rect.height + _actionGap,
                  width: _rect.width,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final (i, action) in NoteAction.values.indexed)
                        _Enter(
                          // right button first, the others a beat later each
                          t: Interval(
                            (NoteAction.values.length - 1 - i) * .12,
                            1,
                            curve: Curves.easeOut,
                          ).transform(_intro.value),
                          child: _ActionButton(
                            action: action,
                            active: hovered == action,
                            onTap: () => _close(action),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Live filter from the nav bar's search field.
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? notes
        : notes.where((n) => n.title.toLowerCase().contains(q)).toList();

    return CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.dark),
      // Nothing here provides a DefaultTextStyle the way Material's Scaffold
      // did, so without this every Text falls back to the yellow-underline
      // debug style.
      child: Builder(
        builder: (context) => DefaultTextStyle(
          style: CupertinoTheme.of(context).textTheme.textStyle,
          child: CupertinoPageScaffold(
            backgroundColor: _bg,
            child: CustomScrollView(
              slivers: [
                CupertinoSliverNavigationBar.search(
                  largeTitle: const Text('All notes'),
                  backgroundColor: _bg,
                  border: null,
                  automaticallyImplyLeading: false,
                  // iOS puts compose in the nav bar; it has no FAB.
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    onPressed: () {},
                    child: const Icon(CupertinoIcons.square_pencil, size: 24),
                  ),
                  searchField: CupertinoSearchTextField(
                    placeholder: 'Search',
                    borderRadius: BorderRadius.circular(30),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  // The 16px gap lives inside each item rather than in a
                  // separator, so a collapsing slot takes its gap with it and
                  // the list closes up by exactly one slot.
                  sliver: SliverList.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final note = visible[i];
                      final key = _keys.putIfAbsent(note, GlobalKey.new);
                      final item = Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GestureDetector(
                          onLongPressStart: (d) =>
                              _pressStart(note, d.localPosition),
                          onLongPressMoveUpdate: (d) =>
                              _pressMove(d.localPosition),
                          onLongPressEnd: (_) => _pressEnd(),
                          onLongPressCancel: _pressEnd,
                          child: NoteCard(key: key, note: note),
                        ),
                      );
                      if (note != _collapsing) return item;
                      // Already folded shut in the overlay, so it holds the
                      // shrinking space without drawing anything.
                      return SizeTransition(
                        sizeFactor: CurvedAnimation(
                          parent: _collapse,
                          curve: Curves.easeInOutCubic,
                        ),
                        alignment: Alignment.topCenter,
                        child: IgnorePointer(
                          child: Opacity(opacity: 0, child: item),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

void main() => runApp(
      const CupertinoApp(
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(brightness: Brightness.dark),
        home: StickyNotesView(),
      ),
    );
