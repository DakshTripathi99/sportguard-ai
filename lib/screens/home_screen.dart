import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main_shell.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName ?? 'User';
    final userEmail = user?.email ?? 'No email';

    return Scaffold(
      backgroundColor: const Color(0xFFE6EEC9),
      drawer: _buildDrawer(userName, userEmail),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            backgroundColor: const Color(0xFF35858E),
            iconTheme: const IconThemeData(color: Colors.white),
            expandedHeight: MediaQuery.of(context).size.height * 0.9,
            floating: false,
            pinned: true,
            centerTitle: true,
            title: InkWell(
              onTap: () {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.security, color: Color(0xFFC2D099), size: 28),
                  SizedBox(width: 8),
                  Text(
                    'SportGuard AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF35858E), Color(0xFF7DA78C)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.security,
                        size: 100,
                        color: Color(0xFFC2D099),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Welcome $userName!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - kToolbarHeight,
              ),
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
              child: Column(
                children: [
                  const Text(
                    'What would you like to do today?',
                    style: TextStyle(
                      color: Color(0xFF35858E),
                      fontSize: 18,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      AnimatedHoverTile(
                        title: 'Upload Asset',
                        subtitle:
                            'Protect new proprietary media by fingerprinting it securely into the database.',
                        icon: Icons.upload_file,
                        gradientColors: const [
                          Color(0xFF35858E),
                          Color(0xFF7DA78C),
                        ],
                        onTap: () => _navigateToShell(context, 1),
                      ),
                      AnimatedHoverTile(
                        title: 'Violations',
                        subtitle:
                            'Review and manage unauthorized usages of your protected digital media.',
                        icon: Icons.warning_amber_rounded,
                        gradientColors: const [
                          Color(0xFF7DA78C),
                          Color(0xFFC2D099),
                        ],
                        onTap: () => _navigateToShell(context, 0),
                      ),
                      AnimatedHoverTile(
                        title: 'Analytics',
                        subtitle:
                            'Track your overall protection metrics, resolution rates, and trends.',
                        icon: Icons.analytics_outlined,
                        gradientColors: const [
                          Color(0xFF35858E),
                          Color(0xFFC2D099),
                        ],
                        onTap: () => _navigateToShell(context, 2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToShell(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MainShell(initialIndex: index)),
    );
  }

  Widget _buildDrawer(String userName, String userEmail) {
    return Drawer(
      backgroundColor: const Color(0xFFE6EEC9),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF35858E)),
            accountName: Text(
              userName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            accountEmail: Text(
              userEmail,
              style: const TextStyle(color: Color(0xFFE6EEC9)),
            ),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Color(0xFFC2D099),
              child: Icon(Icons.person, size: 40, color: Color(0xFF35858E)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Log Out',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
    );
  }
}

class AnimatedHoverTile extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final VoidCallback onTap;

  const AnimatedHoverTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.onTap,
  });

  @override
  State<AnimatedHoverTile> createState() => _AnimatedHoverTileState();
}

class _AnimatedHoverTileState extends State<AnimatedHoverTile> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          width: 280,
          height: isHovered ? 300 : 160,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              colors: [
                widget.gradientColors[0].withValues(
                  alpha: isHovered ? 0.9 : 0.8,
                ),
                widget.gradientColors[1].withValues(
                  alpha: isHovered ? 0.8 : 0.7,
                ),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              if (isHovered)
                BoxShadow(
                  color: widget.gradientColors[0].withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
            ],
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: isHovered ? 0.3 : 0.1,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.icon,
                    color: Colors.white,
                    size: isHovered ? 40 : 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (isHovered) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
