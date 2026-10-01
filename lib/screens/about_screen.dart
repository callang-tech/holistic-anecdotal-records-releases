import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<String> loadApplicationVersion() async {
  final manifest = await rootBundle.loadString('pubspec.yaml');
  final match =
      RegExp(r'^version:\s*([^\s+]+)', multiLine: true).firstMatch(manifest);
  if (match == null) throw StateError('Application version is unavailable.');
  return match.group(1)!;
}

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  late final Future<String> _version = loadApplicationVersion();
  static const _ink = Color(0xFF203F50);
  static const _teal = Color(0xFF216C68);

  @override
  Widget build(BuildContext context) {
    // A local light palette keeps the About page readable in every app theme.
    final theme = Theme.of(context);
    final aboutTheme = theme.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _teal,
        brightness: Brightness.light,
      ),
      textTheme: theme.textTheme.apply(bodyColor: _ink, displayColor: _ink),
    );
    return Theme(
      data: aboutTheme,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F8FB),
        appBar: AppBar(
          title: const Text('About'),
          backgroundColor: const Color(0xFFF3F8FB),
          foregroundColor: _ink,
          elevation: 0,
        ),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEDF5FC), Color(0xFFF0F8F3)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(builder: (context, constraints) {
              final padding = constraints.maxWidth < 600 ? 16.0 : 32.0;
              return SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _header(context),
                        const SizedBox(height: 24),
                        _card(context,
                            heading: 'ABOUT THE SYSTEM',
                            child: const Text(
                              'Holistic Anecdotal Records is a digital application developed to support '
                              'the Care Center Office of Callang National High School in organizing, '
                              'maintaining, and retrieving learner anecdotal records.\n\n'
                              "The application augments the school's existing guidance processes by "
                              'providing a structured digital environment for learner information, '
                              'school history, anecdotal records, and related guidance documentation. '
                              'It is intended to assist, not replace, the professional judgment and '
                              'established procedures of the Guidance Counselor.',
                            )),
                        const SizedBox(height: 20),
                        _card(context,
                            heading: 'SYSTEM LEADERSHIP',
                            prominent: true,
                            child: _leadership(context)),
                        const SizedBox(height: 20),
                        _card(context,
                            heading: 'INSTITUTION',
                            child: _institution(context)),
                        const SizedBox(height: 20),
                        _card(context,
                            heading: 'PRIVACY & INTENDED USE',
                            child: const Text(
                              'This application is intended for authorized school guidance use. '
                              'Information contained in the system should be handled in accordance '
                              'with applicable school policies, privacy requirements, and established '
                              'guidance procedures.',
                            )),
                        const SizedBox(height: 28),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _heading(context, 'ACKNOWLEDGEMENTS'),
                              const SizedBox(height: 12),
                              const Text(
                                'We acknowledge the support of the school administrators, faculty, and '
                                'staff of Callang National High School, and all who contributed ideas, '
                                'feedback, and encouragement in the development and improvement of this '
                                'application.',
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Special acknowledgement to Joven A. Danipog for the technical development and IT support, '
                                'including application programming, database implementation, user interface, '
                                'synchronization, testing, and technical refinements.',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(color: Color(0xFFD3E3E8)),
                        const SizedBox(height: 12),
                        FutureBuilder<String>(
                          future: _version,
                          builder: (context, snapshot) => Text(
                            'Holistic Anecdotal Records • Version ${snapshot.data ?? 'Unavailable'}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Initial Release • 2026',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(children: [
      // All About images are bundled assets, with no external overrides.
      Image.asset('assets/images/about/app_logo.png',
          height: 156,
          fit: BoxFit.contain,
          semanticLabel: 'Holistic Anecdotal Records logo'),
      const SizedBox(height: 18),
      Text('Holistic Anecdotal Records',
          textAlign: TextAlign.center,
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Holistic Educational Anecdotal Record & Tracking System',
          textAlign: TextAlign.center, style: text.titleMedium),
      const SizedBox(height: 16),
      Text('Organize • Monitor • Support • Empower Learners',
          textAlign: TextAlign.center,
          style: text.titleSmall
              ?.copyWith(color: _teal, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('Supporting Learners for a Brighter Tomorrow',
          textAlign: TextAlign.center, style: text.bodySmall),
    ]);
  }

  Widget _heading(BuildContext context, String title) => Text(title,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: _teal, fontWeight: FontWeight.w700, letterSpacing: 1.2));

  Widget _card(BuildContext context,
      {required String heading,
      required Widget child,
      bool prominent = false}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        gradient: prominent
            ? const LinearGradient(
                colors: [Color(0xFFFFFFFF), Color(0xFFEAF5F2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color:
                prominent ? const Color(0xFFB7D8D1) : const Color(0xFFDCE7ED)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x080F4259), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(height: 1.55),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _heading(context, heading),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _leadership(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, constraints) {
      final portrait = ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.asset('assets/images/about/project_leader.jpg',
            width: 176,
            height: 220,
            fit: BoxFit.cover,
            alignment: const Alignment(-0.15, -0.35),
            semanticLabel: 'Michelle A. Carpio, RGC'),
      );
      final attribution = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Michelle A. Carpio, RGC',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('System Lead and Guidance Process Designer',
              style: text.titleMedium
                  ?.copyWith(color: _teal, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Guidance Counselor, Care Center Office'),
          const SizedBox(height: 16),
          const Text(
            'Directed the development of the system and defined the guidance processes, '
            'record requirements, workflow, and functional requirements that form its '
            'foundation. Provides the professional guidance, content expertise, and '
            'overall direction in the continuous improvement of the system for the '
            'benefit of the learners.',
          ),
        ],
      );
      if (constraints.maxWidth < 640) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: portrait),
            const SizedBox(height: 24),
            attribution,
          ],
        );
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        portrait,
        const SizedBox(width: 28),
        Expanded(child: attribution),
      ]);
    });
  }

  Widget _institution(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 16 / 7,
          child: Image.asset('assets/images/about/school.jpg',
              fit: BoxFit.cover,
              semanticLabel: 'Callang National High School photograph'),
        ),
      ),
      const SizedBox(height: 18),
      Text('Callang National High School',
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('District 4, San Manuel, Isabela'),
      const Text('Region II, Philippines'),
      const SizedBox(height: 12),
      const Text(
          'Developed for the Care Center Office of Callang National High School.'),
    ]);
  }
}
