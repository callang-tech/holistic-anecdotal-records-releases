import 'package:flutter/material.dart';

import '../widgets/app_background.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
      ),
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 900,
                ),
                child: Card(
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      32,
                      32,
                      32,
                      28,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: 30),

                        _section(
                          context,
                          icon: Icons.info_outline_rounded,
                          title: 'About the Project',
                          text:
                              'The Holistic Educational Anecdotal Record & '
                              'Tracking System is a digital record-management '
                              'application developed to support the Care Center '
                              'Office in organizing, maintaining, retrieving, '
                              'and tracking learner anecdotal records and '
                              'related guidance information.',
                        ),

                        const SizedBox(height: 4),

                        // Guidance-led project attribution and project information.
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 700;

                            final guidanceProfile = _personCard(
                              context,
                              name: 'Michelle A. Carpio, RGC',
                              role: 'Project Lead and System Proponent',
                              office:
                                  'Guidance Counselor, Care Center Office',
                              description:
                                  'The project was conceptualized and '
                                  'developed under her leadership as an '
                                  'innovation of the Care Center Office. She '
                                  'identified the needs addressed by the '
                                  'system and directed its guidance processes, '
                                  'record requirements, workflow, functional '
                                  'requirements, and continuing development.',
                            );

                            final projectInformation = Column(
                              children: [
                                _section(
                                  context,
                                  icon: Icons.school_outlined,
                                  title: 'Institution',
                                  text:
                                      'Callang National High School\n'
                                      'District 4, San Manuel, Isabela\n'
                                      'Region II, Philippines',
                                ),
                                _section(
                                  context,
                                  icon: Icons.flag_outlined,
                                  title: 'Purpose',
                                  text:
                                      'This application is intended to assist '
                                      'the Care Center Office in improving the '
                                      'organization, accessibility, continuity, '
                                      'and management of learner anecdotal '
                                      'records. It supports the existing '
                                      'guidance system and does not replace '
                                      'the professional judgment, '
                                      'responsibilities, or established '
                                      'procedures of the Guidance Counselor.',
                                ),
                                _section(
                                  context,
                                  icon: Icons.privacy_tip_outlined,
                                  title: 'Data and Privacy',
                                  text:
                                      'Learner and guidance records handled '
                                      'through this application are intended '
                                      'for authorized school use. Users are '
                                      'responsible for observing applicable '
                                      'school policies and data-privacy '
                                      'requirements when accessing, storing, '
                                      'sharing, printing, backing up, or '
                                      'synchronizing records.',
                                ),
                              ],
                            );

                            if (!isWide) {
                              return Column(
                                children: [
                                  guidanceProfile,
                                  const SizedBox(height: 24),
                                  projectInformation,
                                ],
                              );
                            }

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: guidanceProfile,
                                ),
                                const SizedBox(width: 28),
                                Expanded(
                                  flex: 6,
                                  child: projectInformation,
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 8),

                        // Technical support is intentionally presented as a
                        // secondary supporting role beneath the system proponent.
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(maxWidth: 430),
                            child: _personCard(
                              context,
                              name: 'Joven Danipog',
                              role: 'Technical Support',
                              office:
                                  'Application Programming and IT Support',
                              description:
                                  'Provided technical assistance for the '
                                  'digital implementation of the project, '
                                  'including application programming, '
                                  'database setup, interface development, '
                                  'synchronization, testing, and related '
                                  'technical support.',
                            ),
                          ),
                        ),

                        const Divider(height: 34),

                        Text(
                          'Developed for the Care Center Office of '
                          'Callang National High School.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.favorite_rounded,
            size: 34,
            color: colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Holistic Educational Anecdotal\n'
          'Record & Tracking System',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
        ),
        const SizedBox(height: 10),
        Text(
          'Callang National High School',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'District 4, San Manuel, Isabela • Region II',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _personCard(
    BuildContext context, {
    required String name,
    required String role,
    required String office,
    required String description,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow
            .withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: colors.outlineVariant
              .withValues(alpha: 0.75),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Passport-size portrait placeholder.
          Container(
            width: 105,
            height: 135,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colors.outlineVariant,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 46,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  'PHOTO',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(
                        color: colors.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            role,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            office,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 14),
          Divider(
            color: colors.outlineVariant,
          ),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.left,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
                  height: 1.45,
                ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String text,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 21,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
