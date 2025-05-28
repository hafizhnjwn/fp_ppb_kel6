import 'package:fp_pbb_kel6/screens/home_page.dart';
import 'package:fp_pbb_kel6/screens/login.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fp_pbb_kel6/screens/user_page.dart';
import 'package:fp_pbb_kel6/screens/create_post.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  int _currentPageIndex = 0;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final List<Widget> pages = [
            HomePage(userSnaphot: snapshot),
            Center(child: Text("Placeholder")), // Explore Page
            const CreatePostScreen(), // Create Page
            UserPage(userSnaphot: snapshot),
          ];
          return Scaffold(
            body: pages[_currentPageIndex],
            bottomNavigationBar: Container(
              height: 70,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[900]!, width: 0.5)),
              ),
              child: NavigationBar(
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                indicatorColor: Colors.transparent,
                backgroundColor: Colors.black,
                selectedIndex: _currentPageIndex,
                onDestinationSelected: (int index) {
                  setState(() {
                    _currentPageIndex = index;
                  });
                },
                destinations: const <Widget>[
                  NavigationDestination(
                    selectedIcon: Icon(Icons.home),
                    icon: Icon(Icons.home_outlined),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    selectedIcon: Icon(Icons.search_outlined),
                    icon: Icon(Icons.search),
                    label: 'Profile',
                  ),
                  NavigationDestination(
                    selectedIcon: Icon(Icons.add_box),
                    icon: Icon(Icons.add_box_outlined),
                    label: 'Create',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
          );
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}
