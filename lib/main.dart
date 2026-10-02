import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'firebase_options.dart';
import 'services/api_service.dart';
import 'services/delivery_tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FoodDeliveryApp());
}

final CartStore cartStore = CartStore();
final deliveryTrackingService = DeliveryTrackingService();

class SellerMenuStore extends ChangeNotifier {
  final items = <Map<String, dynamic>>[
    {
      'name': 'Classic Burger',
      'description': 'Beef, cheddar, lettuce and house sauce',
      'price': 5.99,
      'category': 'Burgers',
      'available': true,
      'imageBytes': null,
    },
    {
      'name': 'French Fries',
      'description': 'Crispy golden fries with sea salt',
      'price': 2.99,
      'category': 'Sides',
      'available': true,
      'imageBytes': null,
    },
  ];

  Future<void> syncRestaurantMenu(String restaurantName) async {
    final name = restaurantName.trim();
    if (name.isEmpty) {
      items.clear();
      notifyListeners();
      return;
    }

    final menu = await deliveryTrackingService.fetchMenuForRestaurant(name);
    items
      ..clear()
      ..addAll(
        menu.map((entry) => {
          'id': entry['id'],
          'name': entry['name'],
          'description': entry['description'] ?? '',
          'price': (entry['price'] as num?)?.toDouble() ?? 0.0,
          'category': entry['category'] ?? 'General',
          'available': entry['available'] as bool? ?? true,
          'imageBytes': null,
          'imagePath': entry['imagePath'] ?? '',
          'restaurantName': entry['restaurantName'],
        }),
      );
    notifyListeners();
  }

  Future<void> addForRestaurant(
    String restaurantName,
    Map<String, dynamic> item,
  ) async {
    final sanitized = {
      ...item,
      'restaurantName': restaurantName,
      'available': item['available'] as bool? ?? true,
      'imageBytes': item['imageBytes'],
      'imagePath': item['imagePath'] ?? '',
    };

    final id = await deliveryTrackingService.saveMenuItem(
      restaurantName: restaurantName,
      name: sanitized['name'] as String? ?? 'Menu item',
      description: sanitized['description'] as String? ?? '',
      price: (sanitized['price'] as num?)?.toDouble() ?? 0,
      category: sanitized['category'] as String? ?? 'General',
      available: sanitized['available'] as bool? ?? true,
      imagePath: sanitized['imagePath'] as String?,
    );

    sanitized['id'] = id;
    items.insert(0, sanitized);
    notifyListeners();
  }

  void add(Map<String, dynamic> item) {
    items.insert(0, item);
    notifyListeners();
  }

  Future<void> setAvailabilityForRestaurant(
    String restaurantName,
    Map<String, dynamic> item,
    bool value,
  ) async {
    final itemId = item['id'] as String?;
    if (itemId != null && itemId.isNotEmpty) {
      await deliveryTrackingService.updateMenuAvailability(itemId, available: value);
    }
    item['available'] = value;
    notifyListeners();
  }

  void setAvailability(Map<String, dynamic> item, bool value) {
    item['available'] = value;
    notifyListeners();
  }
}

final sellerMenuStore = SellerMenuStore();

Widget dashboardForRole(String? role) {
  switch (role) {
    case 'admin':
      return const AdminDashboardScreen();
    case 'seller':
      return const MainNavigation(role: 'seller');
    case 'driver':
      return const MainNavigation(role: 'driver');
    case 'customer':
      return const MainNavigation(role: 'customer');
    default:
      return const MainNavigation();
  }
}

class CartEntry {
  final String name;
  final String restaurantName;
  final double price;
  final String imagePath;
  int quantity;

  CartEntry({
    required this.name,
    required this.restaurantName,
    required this.price,
    required this.imagePath,
    this.quantity = 1,
  });

  double get total => price * quantity;
}

class CartStore extends ChangeNotifier {
  final List<CartEntry> items = [];
  String? appliedPromo;
  double promoDiscount = 0;

  double get subtotal => items.fold(0, (total, item) => total + item.total);
  double get deliveryFee => items.isEmpty ? 0 : 1.50;
  double get serviceFee => items.isEmpty ? 0 : subtotal * 0.05;
  double get total => double.parse(
    (subtotal + deliveryFee + serviceFee - promoDiscount)
        .clamp(0, double.infinity)
        .toStringAsFixed(2),
  );

  bool applyPromo(String code) {
    if (code.trim().toUpperCase() != 'FOODGO10' || subtotal <= 0) return false;
    appliedPromo = 'FOODGO10';
    promoDiscount = double.parse((subtotal * 0.10).toStringAsFixed(2));
    notifyListeners();
    return true;
  }

  void removePromo() {
    appliedPromo = null;
    promoDiscount = 0;
    notifyListeners();
  }

  void addItem({
    required String name,
    required String restaurantName,
    required String price,
    required String imagePath,
  }) {
    final parsedPrice =
        double.tryParse(price.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final existing = items.where((item) => item.name == name).firstOrNull;
    if (existing != null) {
      existing.quantity++;
    } else {
      items.add(
        CartEntry(
          name: name,
          restaurantName: restaurantName,
          price: parsedPrice,
          imagePath: imagePath,
        ),
      );
    }
    notifyListeners();
  }

  void increment(CartEntry item) {
    item.quantity++;
    notifyListeners();
  }

  void decrement(CartEntry item) {
    if (item.quantity <= 1) {
      items.remove(item);
    } else {
      item.quantity--;
    }
    notifyListeners();
  }

  void clear() {
    items.clear();
    removePromo();
    notifyListeners();
  }
}

class FoodDeliveryApp extends StatelessWidget {
  const FoodDeliveryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FoodGo',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF6B35)),
        scaffoldBackgroundColor: const Color(0xFFF8F8F8),
      ),
      home: const SplashScreen(),
    );
  }
}

// ============================================================
// SPLASH SCREEN
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _openApp();
  }

  Future<void> _openApp() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    Widget destination = const LoginScreen();
    try {
      final profile = await ApiService().restoreSession();
      if (profile != null) {
        destination = dashboardForRole(profile['role'] as String?);
      }
    } on ApiException {
      // Keep the login screen available if the saved session cannot be restored.
    }
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFF6B35),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Icon(
                Icons.restaurant,
                size: 55,
                color: Color(0xFFFF6B35),
              ),
            ),

            const SizedBox(height: 25),

            const Text(
              'FoodGo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Delicious food, delivered fast.',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// MAIN NAVIGATION
// ============================================================

class AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;

  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
        prefixIcon: Icon(icon, color: const Color(0xFFFF6B35)),
        labelText: label,
        hintText: 'Enter your ${label.toLowerCase()}',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _api = ApiService();
  String? _error;
  bool _loading = false;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }

    if (password.length < 4) {
      setState(() => _error = 'Password must be at least 4 characters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.login(email: email, password: password);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => dashboardForRole(ApiService.user?['role'] as String?),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to connect to the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF3EE), Color(0xFFFFF8F4)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 86,
                    height: 86,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35),
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B35).withValues(alpha: 0.28),
                          blurRadius: 18,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.restaurant_menu_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                  const Text(
                    'FoodGo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to continue ordering your favorites.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 15),
                  ),
                  const SizedBox(height: 26),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 8),
                          AuthField(
                            controller: _emailController,
                            label: 'Email address',
                            icon: Icons.email_outlined,
                          ),
                          const SizedBox(height: 16),
                          AuthField(
                            controller: _passwordController,
                            label: 'Password',
                            icon: Icons.lock_outline,
                            obscure: true,
                          ),
                          const SizedBox(height: 14),
                          if (_error != null)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE7E8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _loading ? null : _login,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B35),
                              minimumSize: const Size.fromHeight(54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SignupScreen(),
                              ),
                            ),
                            child: const Text('Create new account'),
                          ),
                          TextButton(
                            onPressed: () => _showForgotPassword(context),
                            child: const Text('Forgot password?'),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MainNavigation(),
                              ),
                            ),
                            child: const Text('Continue as guest'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showForgotPassword(BuildContext context) async {
    final controller = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email address'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty || !email.contains('@') || !mounted) {
      return;
    }
    try {
      await _api.forgotPassword(email);
      if (mounted) {
        setState(
          () => _error = 'If that email exists, a reset link has been sent.',
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _restaurantNameController = TextEditingController();
  final _api = ApiService();
  String? _error;
  bool _loading = false;
  String _selectedRole = 'customer';

  Future<void> _signup() async {
    if (_nameController.text.trim().length < 2) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    if (_emailController.text.trim().isEmpty ||
        !_emailController.text.contains('@')) {
      setState(() => _error = 'Please enter a valid email.');
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your phone number.');
      return;
    }
    if (_selectedRole == 'seller' &&
        _restaurantNameController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your restaurant name.');
      return;
    }
    if (_passwordController.text.trim().length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _api.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        password: _passwordController.text.trim(),
        role: _selectedRole,
        restaurantName: _restaurantNameController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => dashboardForRole(ApiService.user?['role'] as String?),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to connect to the server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF8F4), Color(0xFFFFF1EB)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 10),
                const Text(
                  'Create your account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Join FoodGo and pick the role that matches you.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 24),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AuthField(
                          controller: _nameController,
                          label: 'Full name',
                          icon: Icons.person_outline,
                        ),
                        const SizedBox(height: 16),
                        AuthField(
                          controller: _emailController,
                          label: 'Email address',
                          icon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 16),
                        AuthField(
                          controller: _phoneController,
                          label: 'Phone number',
                          icon: Icons.phone_outlined,
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Choose your role',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _RoleChip(
                              label: 'Customer',
                              icon: Icons.person_rounded,
                              value: 'customer',
                              selected: _selectedRole == 'customer',
                              onSelected: () => setState(() => _selectedRole = 'customer'),
                            ),
                            _RoleChip(
                              label: 'Seller',
                              icon: Icons.storefront_rounded,
                              value: 'seller',
                              selected: _selectedRole == 'seller',
                              onSelected: () => setState(() => _selectedRole = 'seller'),
                            ),
                            _RoleChip(
                              label: 'Driver',
                              icon: Icons.delivery_dining_rounded,
                              value: 'driver',
                              selected: _selectedRole == 'driver',
                              onSelected: () => setState(() => _selectedRole = 'driver'),
                            ),
                          ],
                        ),
                        if (_selectedRole == 'seller') ...[
                          const SizedBox(height: 16),
                          AuthField(
                            controller: _restaurantNameController,
                            label: 'Restaurant name',
                            icon: Icons.store_mall_directory_outlined,
                          ),
                        ],
                        const SizedBox(height: 16),
                        AuthField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscure: true,
                        ),
                        const SizedBox(height: 20),
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(10),
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE7E8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        FilledButton(
                          onPressed: _loading ? null : _signup,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B35),
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Create account',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Already have an account? Sign in'),
                        ),
                      ],
                    ),
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

class _RoleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final bool selected;
  final VoidCallback onSelected;

  const _RoleChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? Colors.white : const Color(0xFF1D1D1F);

    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: textColor),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: textColor)),
        ],
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      backgroundColor: const Color(0xFFF5F5F5),
      selectedColor: const Color(0xFFFF6B35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      side: BorderSide.none,
    );
  }
}

class RoleDashboardScreen extends StatelessWidget {
  final String role;

  const RoleDashboardScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isSeller = role == 'seller';
    final title = isSeller ? 'Seller dashboard' : 'Driver dashboard';
    final subtitle = isSeller
        ? 'Manage your restaurant and incoming orders.'
        : 'View delivery tasks assigned to you.';
    final icon = isSeller
        ? Icons.storefront_outlined
        : Icons.delivery_dining_outlined;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(icon, size: 42, color: const Color(0xFFFF6B35)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Welcome, ${ApiService.user?['name'] ?? role}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (isSeller) ...[
              const Row(
                children: [
                  Expanded(
                    child: _RoleMetric(
                      label: 'Today sales',
                      value: '\$128.40',
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _RoleMetric(
                      label: 'Orders',
                      value: '12',
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.storefront, color: Color(0xFFFF6B35)),
                  title: Text('Store status'),
                  subtitle: Text('Open for customer orders'),
                  trailing: Icon(
                    Icons.toggle_on,
                    color: Colors.green,
                    size: 34,
                  ),
                ),
              ),
              const Card(
                child: ListTile(
                  leading: Icon(
                    Icons.restaurant_menu,
                    color: Color(0xFFFF6B35),
                  ),
                  title: Text('Manage menu'),
                  subtitle: Text('12 items · 10 available'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ),
              const Card(
                child: ListTile(
                  leading: Icon(
                    Icons.pending_actions,
                    color: Color(0xFFFF6B35),
                  ),
                  title: Text('Incoming orders'),
                  subtitle: Text('3 orders need your attention'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ),
            ] else ...[
              const Row(
                children: [
                  Expanded(
                    child: _RoleMetric(
                      label: 'Today earnings',
                      value: '\$46.50',
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _RoleMetric(
                      label: 'Rating',
                      value: '4.9',
                      icon: Icons.star_outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.route, color: Color(0xFFFF6B35)),
                  title: Text('Delivery queue'),
                  subtitle: Text('2 deliveries available nearby'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.location_on, color: Color(0xFFFF6B35)),
                  title: Text('Current status'),
                  subtitle: Text('You are available for deliveries'),
                  trailing: Icon(
                    Icons.toggle_on,
                    color: Colors.green,
                    size: 34,
                  ),
                ),
              ),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.history, color: Color(0xFFFF6B35)),
                  title: Text('Delivery history'),
                  subtitle: Text('View completed deliveries'),
                  trailing: Icon(Icons.chevron_right),
                ),
              ),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: () async {
                await ApiService().logout();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (_) => false,
                  );
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _RoleMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFF6B35)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class AddressRecord {
  final String id;
  final String label;
  final String fullAddress;
  final String city;
  final bool isDefault;
  final double? latitude;
  final double? longitude;

  const AddressRecord({
    required this.id,
    required this.label,
    required this.fullAddress,
    required this.city,
    this.isDefault = false,
    this.latitude,
    this.longitude,
  });
}

class AddressStore extends ChangeNotifier {
  String selectedAddressId = 'home';

  final List<AddressRecord> addresses = [
    const AddressRecord(
      id: 'home',
      label: 'Home',
      fullAddress: 'No. 128, Street 5, Boeng Keng Kang, Phnom Penh',
      city: 'Phnom Penh',
      isDefault: true,
    ),
    const AddressRecord(
      id: 'work',
      label: 'Work',
      fullAddress: 'Sky Tower, #24, Monivong Blvd, Phnom Penh',
      city: 'Phnom Penh',
    ),
  ];

  AddressRecord get selectedAddress => addresses.firstWhere(
    (address) => address.id == selectedAddressId,
    orElse: () => addresses.isEmpty
        ? const AddressRecord(
            id: 'unselected',
            label: 'Choose an address',
            fullAddress: 'Select a delivery location',
            city: '',
          )
        : addresses.first,
  );

  void select(String id) {
    if (!addresses.any((address) => address.id == id)) return;
    selectedAddressId = id;
    notifyListeners();
  }

  AddressRecord addAddress(
    String label,
    String address,
    String city, {
    double? latitude,
    double? longitude,
    bool selectAddress = false,
  }) {
    final record = AddressRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      label: label,
      fullAddress: address,
      city: city,
      latitude: latitude,
      longitude: longitude,
    );
    addresses.add(record);
    if (selectAddress) selectedAddressId = record.id;
    notifyListeners();
    return record;
  }

  void updateAddress(String id, String label, String address, String city) {
    final index = addresses.indexWhere((a) => a.id == id);
    if (index == -1) return;
    addresses[index] = AddressRecord(
      id: id,
      label: label,
      fullAddress: address,
      city: city,
      isDefault: addresses[index].isDefault,
      latitude: addresses[index].latitude,
      longitude: addresses[index].longitude,
    );
    notifyListeners();
  }

  void deleteAddress(String id) {
    addresses.removeWhere((a) => a.id == id);
    if (selectedAddressId == id && addresses.isNotEmpty) {
      selectedAddressId = addresses.first.id;
    }
    if (addresses.isEmpty) {
      notifyListeners();
      return;
    }
    if (!addresses.any((a) => a.isDefault)) {
      final first = addresses.first;
      addresses[0] = AddressRecord(
        id: first.id,
        label: first.label,
        fullAddress: first.fullAddress,
        city: first.city,
        isDefault: true,
        latitude: first.latitude,
        longitude: first.longitude,
      );
    }
    notifyListeners();
  }

  void setDefault(String id) {
    for (var i = 0; i < addresses.length; i++) {
      addresses[i] = AddressRecord(
        id: addresses[i].id,
        label: addresses[i].label,
        fullAddress: addresses[i].fullAddress,
        city: addresses[i].city,
        isDefault: addresses[i].id == id,
        latitude: addresses[i].latitude,
        longitude: addresses[i].longitude,
      );
    }
    notifyListeners();
  }
}

final addressStore = AddressStore();

class AppNotificationItem {
  final String title;
  final String detail;
  final String time;
  final IconData icon;
  final bool unread;

  const AppNotificationItem({
    required this.title,
    required this.detail,
    required this.time,
    required this.icon,
    this.unread = true,
  });
}

class NotificationStore extends ChangeNotifier {
  final List<AppNotificationItem> items = [
    const AppNotificationItem(
      title: 'Order confirmed',
      detail: 'Your Burger House order has been accepted.',
      time: '2 min ago',
      icon: Icons.check_circle,
    ),
    const AppNotificationItem(
      title: 'Delivery update',
      detail: 'Your rider is on the way with your order.',
      time: '12 min ago',
      icon: Icons.delivery_dining,
    ),
    const AppNotificationItem(
      title: 'Promotion',
      detail: 'Use FOODGO10 for extra savings today.',
      time: '1 hour ago',
      icon: Icons.local_offer,
      unread: false,
    ),
  ];

  void markAllRead() {
    for (var i = 0; i < items.length; i++) {
      items[i] = AppNotificationItem(
        title: items[i].title,
        detail: items[i].detail,
        time: items[i].time,
        icon: items[i].icon,
        unread: false,
      );
    }
    notifyListeners();
  }
}

final notificationStore = NotificationStore();

class RoleToolsScreen extends StatefulWidget {
  final String role;

  const RoleToolsScreen({super.key, required this.role});

  @override
  State<RoleToolsScreen> createState() => _RoleToolsScreenState();
}

class _RoleToolsScreenState extends State<RoleToolsScreen> {
  bool _available = true;
  List<Map<String, dynamic>> get _menu => sellerMenuStore.items;

  bool get _isSeller => widget.role == 'seller';

  void _showTrackingError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  void initState() {
    super.initState();
    if (_isSeller) {
      _loadSellerMenu();
    }
    _loadDriverAvailability();
  }

  Future<void> _loadSellerMenu() async {
    final restaurantName = ApiService.user?['restaurantName'] as String? ?? '';
    if (restaurantName.isEmpty) return;
    await sellerMenuStore.syncRestaurantMenu(restaurantName);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadDriverAvailability() async {
    final available = await deliveryTrackingService.getDriverAvailability();
    if (!mounted) return;
    setState(() => _available = available);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF7A3D), Color(0xFFFF6B35)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1AFF6B35),
                  blurRadius: 18,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    _isSeller ? Icons.storefront_rounded : Icons.delivery_dining_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isSeller ? 'Seller workspace' : 'Driver workspace',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hi, ${ApiService.user?['name'] ?? (_isSeller ? 'seller' : 'driver')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            _isSeller
                ? 'Everything you need to run today\'s service.'
                : 'Everything you need for a smooth delivery shift.',
            style: const TextStyle(
              color: Color(0xFF6D6D72),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          if (_isSeller) _sellerTools() else _driverTools(),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFFFF6B35)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Platform status',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Menu, order, and delivery flows are connected and ready for use.',
                        style: TextStyle(color: Color(0xFF6D6D72)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sellerTools() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1EE),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE8DD),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: Color(0xFFFF6B35),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '\$128.40',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Sales today',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1EE),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE8DD),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Color(0xFFFF6B35),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            '12',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Orders',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Store availability',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _available ? 'Accepting orders' : 'Not accepting orders',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _available,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFFFF6B35),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFD7D5D3),
                onChanged: (value) async {
                  setState(() => _available = value);
                  try {
                    await deliveryTrackingService.updateStoreAvailability(
                      available: value,
                    );
                  } catch (error) {
                    if (!mounted) return;
                    setState(() => _available = !value);
                    _showTrackingError(error);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Your menu',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _addFood,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add food'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${_menu.length} items · ${_menu.where((item) => item['available'] == true).length} available',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 14),
              ..._menu.map(_menuItem),
            ],
          ),
        ),
      ],
    );
  }

  Widget _driverTools() {
    return Column(
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: deliveryTrackingService.getDriverDashboardMetrics(),
          builder: (context, snapshot) {
            final stats = snapshot.data ?? const <String, dynamic>{
              'earningsToday': 0.0,
              'completedThisWeek': 0,
              'rating': 4.9,
            };
            final earnings = (stats['earningsToday'] as num?)?.toDouble() ?? 0.0;
            final rating = (stats['rating'] as num?)?.toDouble() ?? 4.9;
            return Row(
              children: [
                Expanded(
                  child: _driverMetricCard(
                    'Earnings today',
                    '\$${earnings.toStringAsFixed(2)}',
                    Icons.payments_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _driverMetricCard(
                    'Rating',
                    rating.toStringAsFixed(1),
                    Icons.star_rounded,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1AFF6B35),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
            title: const Text(
              'Available for deliveries',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            subtitle: Text(
              _available
                  ? 'You can receive delivery requests'
                  : 'You are offline',
              style: const TextStyle(color: Colors.grey),
            ),
            value: _available,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFFFF8A5C),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: const Color(0xFFE7E5E4),
            onChanged: (value) async {
              setState(() => _available = value);
              try {
                await deliveryTrackingService.updateDriverAvailability(
                  available: value,
                );
              } catch (error) {
                if (!mounted) return;
                setState(() => _available = !value);
                _showTrackingError(error);
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: deliveryTrackingService.watchReadyOrders(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text('Unable to load ready deliveries: ${snapshot.error}'),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3EE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.local_shipping_rounded, color: Color(0xFFFF6B35)),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Available deliveries',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text('No orders are ready for pickup.'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: snapshot.data!.docs.map((document) {
                final order = OrderRecord.fromDocument(document);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0FFFB59D),
                        blurRadius: 14,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE8DD),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${order.restaurantName} • ${order.orderNumber}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ready for pickup • ${order.deliveryAddress}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        onPressed: () async {
                          final navigator = Navigator.of(context);
                          try {
                            await deliveryTrackingService.claimOrder(
                              document.id,
                              ApiService.user?['name'] as String? ?? 'Courier',
                            );
                            order.trackingId = document.id;
                            if (!mounted) return;
                            await navigator.push(
                              MaterialPageRoute(
                                builder: (_) => DeliveryTrackingScreen(
                                  order: order,
                                  role: 'driver',
                                ),
                              ),
                            );
                          } catch (error) {
                            _showTrackingError(error);
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B35),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: deliveryTrackingService.watchDriverOrders(),
          builder: (context, snapshot) {
            if (snapshot.hasError || !snapshot.hasData) {
              return const SizedBox.shrink();
            }

            final activeOrders = snapshot.data!.docs
                .where((document) => document.data()['status'] != 'Delivered')
                .toList();

            if (activeOrders.isEmpty) {
              return const SizedBox.shrink();
            }

            return Column(
              children: activeOrders.map((document) {
                final order = OrderRecord.fromDocument(document);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1EB),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.delivery_dining_rounded,
                          color: Color(0xFFFF6B35),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.orderNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Your delivery • ${order.status}',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Open live map',
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DeliveryTrackingScreen(
                              order: order,
                              role: 'driver',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>>(
          future: deliveryTrackingService.getDriverDashboardMetrics(),
          builder: (context, snapshot) {
            final completed = (snapshot.data?['completedThisWeek'] as num?)?.toInt() ?? 0;
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListTile(
                leading: const Icon(Icons.history_rounded, color: Color(0xFFFF6B35)),
                title: const Text(
                  'Delivery history',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                subtitle: Text('$completed completed deliveries this week'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showMessage(
                  'Delivery history will connect when driver endpoints are available.',
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8DD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFFF6B35)),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _driverMetricCard(String label, String value, IconData icon) =>
      _metricCard(label: label, value: value, icon: icon);

  Widget _menuItem(Map<String, dynamic> item) {
    final available = item['available'] as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8DD),
              borderRadius: BorderRadius.circular(12),
            ),
            child: item['imageBytes'] is Uint8List
                ? Image.memory(
                    item['imageBytes'] as Uint8List,
                    fit: BoxFit.cover,
                  )
                : const Icon(Icons.fastfood, color: Color(0xFFFF6B35)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 3),
                Text(
                  item['description'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  '\$${(item['price'] as double).toStringAsFixed(2)} · ${item['category']}',
                  style: const TextStyle(
                    color: Color(0xFFFF6B35),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: available,
            activeThumbColor: const Color(0xFFFF6B35),
            onChanged: (value) async {
              final restaurantName = ApiService.user?['restaurantName'] as String? ?? '';
              if (restaurantName.isNotEmpty) {
                await sellerMenuStore.setAvailabilityForRestaurant(
                  restaurantName,
                  item,
                  value,
                );
              } else {
                sellerMenuStore.setAvailability(item, value);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _addFood() async {
    final item = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AddFoodScreen()),
    );
    if (item == null) return;

    final restaurantName = ApiService.user?['restaurantName'] as String? ?? '';
    if (restaurantName.isEmpty) {
      sellerMenuStore.add(item);
      return;
    }

    await sellerMenuStore.addForRestaurant(restaurantName, item);
  }

  // Kept temporarily for compatibility with the previous seller flow.
  // ignore: unused_element
  Future<void> _addFoodLegacy() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final priceController = TextEditingController();
    final picker = ImagePicker();
    Uint8List? photoBytes;
    var category = 'Burgers';
    final values = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Add new food',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Create a delicious item for your menu.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: () async {
                    final image = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 80,
                    );
                    if (image == null) return;
                    photoBytes = await image.readAsBytes();
                    if (!context.mounted) return;
                    setSheetState(() {});
                  },
                  child: Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8F4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFFE8DD)),
                    ),
                    child: photoBytes == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_photo_alternate_outlined,
                                color: Color(0xFFFF6B35),
                                size: 30,
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Add food photo',
                                style: TextStyle(
                                  color: Color(0xFFFF6B35),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Tap to choose from gallery',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.memory(
                              photoBytes!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Food name',
                    prefixIcon: Icon(Icons.restaurant_menu),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          prefixText: '\$ ',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Burgers',
                            child: Text('Burgers'),
                          ),
                          DropdownMenuItem(
                            value: 'Sides',
                            child: Text('Sides'),
                          ),
                          DropdownMenuItem(
                            value: 'Drinks',
                            child: Text('Drinks'),
                          ),
                          DropdownMenuItem(
                            value: 'Desserts',
                            child: Text('Desserts'),
                          ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => category = value ?? 'Burgers'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, [
                      nameController.text.trim(),
                      descriptionController.text.trim(),
                      priceController.text.trim(),
                      category,
                    ]),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B35),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Add to menu',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nameController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    if (values == null || values[0].isEmpty) return;
    sellerMenuStore.add({
      'name': values[0],
      'description': values[1].isEmpty
          ? 'Freshly prepared for your customers'
          : values[1],
      'price': double.tryParse(values[2]) ?? 0,
      'category': values[3],
      'imageBytes': photoBytes,
      'available': true,
    });
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key});

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _photoBytes;
  String _category = 'Burgers';

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null || !mounted) return;
    final bytes = await image.readAsBytes();
    if (mounted) setState(() => _photoBytes = bytes);
  }

  void _save() {
    final name = _nameController.text.trim();
    final price = double.tryParse(_priceController.text.trim());
    if (name.isEmpty || price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a food name and valid price.')),
      );
      return;
    }
    Navigator.pop(context, {
      'name': name,
      'description': _descriptionController.text.trim().isEmpty
          ? 'Freshly prepared for your customers'
          : _descriptionController.text.trim(),
      'price': price,
      'category': _category,
      'imageBytes': _photoBytes,
      'available': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F4),
      appBar: AppBar(
        title: const Text(
          'Add food',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          const Text(
            'Create a menu item',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add the details customers will see on your menu.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: Container(
                      height: 170,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE8DD),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: _photoBytes == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 38,
                                  color: Color(0xFFFF6B35),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Choose food photo',
                                  style: TextStyle(
                                    color: Color(0xFFFF6B35),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Tap to open gallery',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : Image.memory(_photoBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Food name',
                      prefixIcon: Icon(Icons.restaurant_menu),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Price',
                            prefixText: '\$ ',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _category,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Burgers',
                              child: Text('Burgers'),
                            ),
                            DropdownMenuItem(
                              value: 'Sides',
                              child: Text('Sides'),
                            ),
                            DropdownMenuItem(
                              value: 'Drinks',
                              child: Text('Drinks'),
                            ),
                            DropdownMenuItem(
                              value: 'Desserts',
                              child: Text('Desserts'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _category = value ?? 'Burgers'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text(
                'Add to menu',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  final String? role;

  const MainNavigation({super.key, this.role});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int selectedIndex = 0;

  List<Widget> get pages {
    final pageList = <Widget>[
      const HomeScreen(),
      const SearchScreen(),
      const CartScreen(),
      const OrdersScreen(),
      const ProfileScreen(),
    ];

    if (widget.role == 'seller') {
      pageList.add(RoleToolsScreen(role: 'seller'));
      pageList.add(RoleToolsScreen(role: 'driver'));
    } else if (widget.role == 'driver' || widget.role == 'customer') {
      pageList.add(RoleToolsScreen(role: widget.role!));
    }

    return pageList;
  }

  List<NavigationDestination> get destinations {
    final destinationList = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: 'Search',
      ),
      const NavigationDestination(
        icon: Icon(Icons.shopping_bag_outlined),
        selectedIcon: Icon(Icons.shopping_bag),
        label: 'Cart',
      ),
      const NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: 'Orders',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profile',
      ),
    ];

    if (widget.role == 'seller') {
      destinationList.add(
        const NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront),
          label: 'Store',
        ),
      );
      destinationList.add(
        const NavigationDestination(
          icon: Icon(Icons.delivery_dining_outlined),
          selectedIcon: Icon(Icons.delivery_dining),
          label: 'Deliveries',
        ),
      );
    } else if (widget.role == 'driver' || widget.role == 'customer') {
      destinationList.add(
        const NavigationDestination(
          icon: Icon(Icons.delivery_dining_outlined),
          selectedIcon: Icon(Icons.delivery_dining),
          label: 'Deliveries',
        ),
      );
    }

    return destinationList;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[selectedIndex],

      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,

        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },

        destinations: destinations,
      ),
    );
  }
}

// ============================================================
// HOME SCREEN
// ============================================================

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LOCATION
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0EA),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Color(0xFFFF6B35),
                  ),
                ),

                const SizedBox(width: 12),

                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deliver to',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Phnom Penh, Cambodia',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),

                GestureDetector(
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const NotificationsSheet(),
                  ),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 22),

            const Text(
              'What are you craving?',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 16),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F000000),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search food or restaurants...',
                  hintStyle: const TextStyle(color: Color(0xFF8C8C8E)),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFFF6B35)),
                  suffixIcon: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0EA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFFFF6B35)),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),

            const SizedBox(height: 22),

            Container(
              height: 180,
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF7A3D), Color(0xFFFF5A1F)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x26FF6B35),
                    blurRadius: 18,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'SPECIAL DEAL',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '30% OFF',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Free delivery on your first order',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 122,
                    height: 122,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 12,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/burger house.webp',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // CATEGORIES
            const SectionTitle(title: 'Categories', action: 'See all'),

            const SizedBox(height: 15),

            SizedBox(
              height: 112,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: const [
                  CategoryCard(
                    icon: Icons.lunch_dining,
                    name: 'Burger',
                    imagePath: 'assets/images/burger house.webp',
                  ),
                  CategoryCard(
                    icon: Icons.local_pizza,
                    name: 'Pizza',
                    imagePath: 'assets/images/Pizza.png',
                  ),
                  CategoryCard(
                    icon: Icons.ramen_dining,
                    name: 'Noodles',
                    imagePath: 'assets/images/Noodle.png',
                  ),
                  CategoryCard(
                    icon: Icons.local_cafe,
                    name: 'Drinks',
                    imagePath: 'assets/images/cocacola.png',
                  ),
                  CategoryCard(
                    icon: Icons.icecream,
                    name: 'Dessert',
                    imagePath: 'assets/images/Dessert.png',
                  ),
                  CategoryCard(
                    icon: Icons.set_meal,
                    name: 'Sushi',
                    imagePath: 'assets/images/Sushi.png',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            AnimatedBuilder(
              animation: sellerMenuStore,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(title: 'Fresh from sellers', action: ''),
                  const SizedBox(height: 12),
                  ...sellerMenuStore.items.map(
                    (item) => _SellerFoodHomeCard(item: item),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),

            SectionTitle(
              title: 'Popular Near You',
              action: 'See all',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PopularRestaurantsScreen(),
                ),
              ),
            ),

            const SizedBox(height: 15),

            const RestaurantCard(
              name: 'Burger House',
              cuisine: 'Burgers • Fast Food',
              rating: '4.8',
              time: '20-30 min',
              delivery: '\$1.50 delivery',
            ),

            const RestaurantCard(
              name: 'Pizza Corner',
              cuisine: 'Pizza • Italian',
              rating: '4.7',
              time: '25-35 min',
              delivery: '\$1.00 delivery',
            ),

            const RestaurantCard(
              name: 'Sushi World',
              cuisine: 'Japanese • Sushi',
              rating: '4.9',
              time: '30-40 min',
              delivery: 'Free delivery',
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerFoodHomeCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _SellerFoodHomeCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final imageBytes = item['imageBytes'];
    final available = item['available'] as bool? ?? true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE8DD),
                borderRadius: BorderRadius.circular(14),
              ),
              child: imageBytes is Uint8List
                  ? Image.memory(imageBytes, fit: BoxFit.cover)
                  : const Icon(
                      Icons.fastfood,
                      color: Color(0xFFFF6B35),
                      size: 30,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['name'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (!available)
                        const Text(
                          'Unavailable',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item['description'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${item['category']} · \$${(item['price'] as double).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFFFF6B35),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: available ? 'Add to cart' : 'Unavailable',
              onPressed: available
                  ? () => cartStore.addItem(
                      name: item['name'] as String,
                      restaurantName: 'Seller menu',
                      price:
                          '\$${(item['price'] as double).toStringAsFixed(2)}',
                      imagePath: '',
                    )
                  : null,
              icon: const Icon(Icons.add_circle, color: Color(0xFFFF6B35)),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(28),
      ),
      child: AnimatedBuilder(
        animation: notificationStore,
        builder: (context, _) {
          final items = notificationStore.items;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No notifications yet.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(item.icon, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.detail,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            item.time,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    notificationStore.markAllRead();
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Mark all read'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// CATEGORY CARD
// ============================================================

class CategoryCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final String? imagePath;

  const CategoryCard({
    super.key,
    required this.icon,
    required this.name,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0EA),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 12,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: imagePath == null
                ? Icon(icon, color: const Color(0xFFFF6B35), size: 31)
                : Image.asset(imagePath!, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RESTAURANT CARD
// ============================================================

class RestaurantCard extends StatelessWidget {
  final String name;
  final String cuisine;
  final String rating;
  final String time;
  final String delivery;

  const RestaurantCard({
    super.key,
    required this.name,
    required this.cuisine,
    required this.rating,
    required this.time,
    required this.delivery,
  });

  @override
  Widget build(BuildContext context) {
    final isBurgerHouse = name == 'Burger House';
    final imagePath = name == 'Pizza Corner'
        ? 'assets/images/Pizza.png'
        : name == 'Sushi World'
        ? 'assets/images/Sushi.png'
        : 'assets/images/burger house.webp';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RestaurantScreen(restaurantName: name),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 170,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  isBurgerHouse ||
                          name == 'Pizza Corner' ||
                          name == 'Sushi World'
                      ? Image.asset(imagePath, fit: BoxFit.cover)
                      : const Center(
                          child: Icon(
                            Icons.restaurant,
                            size: 70,
                            color: Color(0xFFFF6B35),
                          ),
                        ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: AnimatedBuilder(
                      animation: favoriteStore,
                      builder: (context, _) {
                        final isFavorite = favoriteStore.contains(name);
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x12000000),
                                blurRadius: 8,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            tooltip: isFavorite
                                ? 'Remove favorite'
                                : 'Save favorite',
                            onPressed: () => favoriteStore.toggle(name),
                            icon: Icon(
                              isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: isFavorite ? Colors.redAccent : Colors.black54,
                              size: 20,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.flash_on_rounded, size: 14, color: Color(0xFFFF6B35)),
                          SizedBox(width: 4),
                          Text(
                            'Fast',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0EA),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              rating,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(cuisine, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 15, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(time, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(width: 14),
                      const Icon(Icons.delivery_dining, size: 15, color: Colors.grey),
                      const SizedBox(width: 5),
                      Text(delivery, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// RESTAURANT SCREEN
// ============================================================

class RestaurantScreen extends StatelessWidget {
  final String restaurantName;

  const RestaurantScreen({super.key, required this.restaurantName});

  @override
  Widget build(BuildContext context) {
    final headerImagePath = restaurantName == 'Pizza Corner'
        ? 'assets/images/Pizza.png'
        : restaurantName == 'Sushi World'
        ? 'assets/images/Sushi.png'
        : 'assets/images/burger house.webp';
    final menuImagePath = restaurantName == 'Pizza Corner'
        ? 'assets/images/Pizza.png'
        : restaurantName == 'Sushi World'
        ? 'assets/images/Sushi.png'
        : null;
    final cuisine = restaurantName == 'Pizza Corner'
        ? 'Pizza • Italian'
        : restaurantName == 'Sushi World'
        ? 'Japanese • Sushi'
        : 'Burgers • Fast Food • Drinks';
    final rating = restaurantName == 'Sushi World'
        ? '4.9'
        : restaurantName == 'Pizza Corner'
        ? '4.7'
        : '4.8';
    final deliveryTime = restaurantName == 'Sushi World'
        ? '30-40 min'
        : restaurantName == 'Pizza Corner'
        ? '25-35 min'
        : '20-30 min';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER IMAGE
              Stack(
                children: [
                  Container(
                    height: 270,
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(color: Color(0xFFFFE8DD)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(headerImagePath, fit: BoxFit.cover),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0x99000000)],
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 18,
                          bottom: 18,
                          child: Row(
                            children: [
                              Icon(
                                Icons.circle,
                                color: Colors.greenAccent,
                                size: 10,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'OPEN NOW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  Positioned(
                    top: 15,
                    left: 15,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 15,
                    right: 15,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: AnimatedBuilder(
                        animation: favoriteStore,
                        builder: (context, _) {
                          final isFavorite = favoriteStore.contains(
                            restaurantName,
                          );
                          return IconButton(
                            onPressed: () =>
                                favoriteStore.toggle(restaurantName),
                            icon: Icon(
                              isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: isFavorite
                                  ? Colors.redAccent
                                  : Colors.black87,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurantName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      cuisine,
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber),
                        SizedBox(width: 5),
                        Text(
                          rating,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 15),
                        Icon(Icons.access_time),
                        SizedBox(width: 5),
                        Text(deliveryTime),
                      ],
                    ),

                    const SizedBox(height: 25),

                    const Text(
                      'Popular',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 15),

                    FoodCard(
                      name: 'Cheese Burger',
                      description:
                          'Beef patty, cheese, lettuce and special sauce',
                      price: '\$5.99',
                      imagePath: menuImagePath,
                      restaurantName: restaurantName,
                    ),

                    FoodCard(
                      name: 'Chicken Burger',
                      description: 'Crispy chicken, lettuce and creamy sauce',
                      price: '\$5.49',
                      imagePath: menuImagePath,
                      restaurantName: restaurantName,
                    ),

                    FoodCard(
                      name: 'French Fries',
                      description: 'Crispy golden french fries',
                      price: '\$2.99',
                      imagePath: menuImagePath,
                      restaurantName: restaurantName,
                    ),

                    FoodCard(
                      name: 'Coca Cola',
                      description: 'Cold refreshing Coca Cola',
                      price: '\$1.50',
                      imagePath: menuImagePath,
                      restaurantName: restaurantName,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FOOD CARD
// ============================================================

class FoodCard extends StatelessWidget {
  final String name;
  final String description;
  final String price;
  final String? imagePath;
  final String restaurantName;

  const FoodCard({
    super.key,
    required this.name,
    required this.description,
    required this.price,
    this.restaurantName = 'Burger House',
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final isBurger = name.contains('Burger');
    final defaultImagePath = name == 'French Fries'
        ? 'assets/images/FrenchFried.png'
        : name == 'Coca Cola'
        ? 'assets/images/cocacola.png'
        : 'assets/images/burger house.webp';
    final resolvedImagePath = name == 'French Fries' || name == 'Coca Cola'
        ? defaultImagePath
        : imagePath ?? (isBurger ? defaultImagePath : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),

      child: Row(
        children: [
          Container(
            width: 90,
            height: 90,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8DD),
              borderRadius: BorderRadius.circular(15),
            ),
            child: resolvedImagePath != null
                ? Image.asset(resolvedImagePath, fit: BoxFit.cover)
                : const Icon(
                    Icons.fastfood,
                    size: 42,
                    color: Color(0xFFFF6B35),
                  ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),

                const SizedBox(height: 8),

                Text(
                  price,
                  style: const TextStyle(
                    color: Color(0xFFFF6B35),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () {
                cartStore.addItem(
                  name: name,
                  restaurantName: restaurantName,
                  price: price,
                  imagePath:
                      resolvedImagePath ?? 'assets/images/burger house.webp',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$name added to your cart'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              icon: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class PopularRestaurantsScreen extends StatefulWidget {
  const PopularRestaurantsScreen({super.key});

  @override
  State<PopularRestaurantsScreen> createState() =>
      _PopularRestaurantsScreenState();
}

class _PopularRestaurantsScreenState extends State<PopularRestaurantsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _filter = 'All';

  final List<PopularRestaurant> _restaurants = const [
    PopularRestaurant(
      'Burger House',
      'Burgers • Fast Food',
      '4.8',
      '20-30 min',
      '\$1.50 delivery',
    ),
    PopularRestaurant(
      'Pizza Corner',
      'Pizza • Italian',
      '4.7',
      '25-35 min',
      '\$1.00 delivery',
    ),
    PopularRestaurant(
      'Sushi World',
      'Japanese • Sushi',
      '4.9',
      '30-40 min',
      'Free delivery',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.toLowerCase();
    final filtered = _restaurants.where((restaurant) {
      final matchesQuery = '${restaurant.name} ${restaurant.cuisine}'
          .toLowerCase()
          .contains(query);
      final matchesFilter =
          _filter == 'All' ||
          (_filter == 'Fast Food' &&
              restaurant.cuisine.contains('Fast Food')) ||
          (_filter == 'Pizza' && restaurant.cuisine.contains('Pizza')) ||
          (_filter == 'Sushi' && restaurant.cuisine.contains('Sushi')) ||
          (_filter == 'Free Delivery' &&
              restaurant.delivery == 'Free delivery');
      return matchesQuery && matchesFilter;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Popular Near You',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Discover your next favorite place',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search restaurants...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: const [
                  'All',
                  'Fast Food',
                  'Pizza',
                  'Sushi',
                  'Free Delivery',
                ].length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  const filters = [
                    'All',
                    'Fast Food',
                    'Pizza',
                    'Sushi',
                    'Free Delivery',
                  ];
                  final filter = filters[index];
                  return ChoiceChip(
                    label: Text(filter),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                    selectedColor: const Color(0xFFFFE8DD),
                    labelStyle: TextStyle(
                      color: _filter == filter
                          ? const Color(0xFFFF6B35)
                          : Colors.black87,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '${filtered.length} restaurants found',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No restaurants match your filters.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final restaurant = filtered[index];
                        return RestaurantCard(
                          name: restaurant.name,
                          cuisine: restaurant.cuisine,
                          rating: restaurant.rating,
                          time: restaurant.time,
                          delivery: restaurant.delivery,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PopularRestaurant {
  final String name;
  final String cuisine;
  final String rating;
  final String time;
  final String delivery;

  const PopularRestaurant(
    this.name,
    this.cuisine,
    this.rating,
    this.time,
    this.delivery,
  );
}

// ============================================================
// SEARCH SCREEN
// ============================================================

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  final List<SearchResult> _results = const [
    SearchResult(
      title: 'Burger House',
      subtitle: 'Burgers • Fast Food',
      imagePath: 'assets/images/burger house.webp',
      restaurantName: 'Burger House',
    ),
    SearchResult(
      title: 'Pizza Corner',
      subtitle: 'Pizza • Italian',
      imagePath: 'assets/images/Pizza.png',
      restaurantName: 'Pizza Corner',
    ),
    SearchResult(
      title: 'Sushi World',
      subtitle: 'Japanese • Sushi',
      imagePath: 'assets/images/Sushi.png',
      restaurantName: 'Sushi World',
    ),
    SearchResult(
      title: 'Cheese Burger',
      subtitle: 'Beef patty, cheese and special sauce',
      imagePath: 'assets/images/burger house.webp',
      restaurantName: 'Burger House',
    ),
    SearchResult(
      title: 'French Fries',
      subtitle: 'Crispy golden french fries',
      imagePath: 'assets/images/FrenchFried.png',
      restaurantName: 'Burger House',
    ),
    SearchResult(
      title: 'Coca Cola',
      subtitle: 'Cold refreshing Coca Cola',
      imagePath: 'assets/images/cocacola.png',
      restaurantName: 'Burger House',
    ),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    setState(() => _query = value);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.trim().toLowerCase();
    final filteredResults = normalizedQuery.isEmpty
        ? <SearchResult>[]
        : _results.where((result) {
            return '${result.title} ${result.subtitle}'.toLowerCase().contains(
              normalizedQuery,
            );
          }).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Search',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextField(
              /*
  final _menu = <Map<String, dynamic>>[
    {'name': 'Classic Burger', 'price': 5.99, 'available': true},
    {'name': 'French Fries', 'price': 2.99, 'available': true},
    {'name': 'Chicken Burger', 'price': 5.49, 'available': false},
  ];
  final _orders = <String, String>{'FG-1042': 'New', 'FG-1039': 'Preparing', 'FG-1034': 'Ready'};
  final _deliveries = <Map<String, String>>[
    {'order': 'FG-1042', 'restaurant': 'Burger House', 'address': 'Street 240, Phnom Penh', 'status': 'Available'},
    {'order': 'FG-1038', 'restaurant': 'Pizza Corner', 'address': 'Monivong Boulevard', 'status': 'Accepted'},
  ];

  bool _storeOpen = true;

  bool get _isSeller => widget.role == 'seller';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSeller ? 'Seller dashboard' : 'Driver dashboard'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _isSeller ? _buildSeller() : _buildDriver(),
    );
  }

  Widget _header(String title, String subtitle, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: const Color(0xFFFFE8DD),
              child: Icon(icon, color: const Color(0xFFFF6B35)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeller() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _header('Welcome, ${ApiService.user?['name'] ?? 'seller'}', 'Manage your store and orders.', Icons.storefront_outlined),
        const SizedBox(height: 14),
        Row(children: [
          _metric('Today', '\$128.40', Icons.payments_outlined),
          const SizedBox(width: 10),
          _metric('Orders', '${_orders.length}', Icons.receipt_long_outlined),
          const SizedBox(width: 10),
          _metric('Menu items', '${_menu.length}', Icons.restaurant_menu),
        ]),
        const SizedBox(height: 20),
        SwitchListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Store is open', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(_storeOpen ? 'Customers can place orders' : 'Store is temporarily closed'),
          value: _storeOpen,
          activeColor: const Color(0xFFFF6B35),
          onChanged: (value) => setState(() => _storeOpen = value),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Menu', 'Add item', _addMenuItem),
        ..._menu.map((item) => Card(
              child: SwitchListTile(
                title: Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('\$${(item['price'] as double).toStringAsFixed(2)}'),
                value: item['available'] as bool,
                activeColor: const Color(0xFFFF6B35),
                onChanged: (value) => setState(() => item['available'] = value),
              ),
            )),
        const SizedBox(height: 12),
        _sectionTitle('Incoming orders', null, null),
        ..._orders.entries.map((entry) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
                title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Demo order status: ${entry.value}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) => setState(() => _orders[entry.key] = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'Preparing', child: Text('Preparing')),
                    PopupMenuItem(value: 'Ready', child: Text('Ready')),
                    PopupMenuItem(value: 'Completed', child: Text('Completed')),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildDriver() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        _header('Welcome, ${ApiService.user?['name'] ?? 'driver'}', 'Keep deliveries moving.', Icons.delivery_dining_outlined),
        const SizedBox(height: 14),
        Row(children: [
          _metric('Today', '\$46.50', Icons.payments_outlined),
          const SizedBox(width: 10),
          _metric('Deliveries', '6', Icons.route_outlined),
          const SizedBox(width: 10),
          _metric('Rating', '4.9', Icons.star_outline),
        ]),
        const SizedBox(height: 20),
        _sectionTitle('Delivery queue', 'Refresh', () => setState(() {})),
        ..._deliveries.map((delivery) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.storefront_outlined, color: Color(0xFFFF6B35)),
                    const SizedBox(width: 10),
                    Expanded(child: Text('${delivery['restaurant']}  •  ${delivery['order']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    Chip(label: Text(delivery['status']!)),
                  ]),
                  const SizedBox(height: 8),
                  Text(delivery['address']!, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton(
                    onPressed: () => setState(() => delivery['status'] = delivery['status'] == 'Available' ? 'Accepted' : delivery['status'] == 'Accepted' ? 'Picked up' : 'Delivered'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF6B35)),
                    child: Text(delivery['status'] == 'Available' ? 'Accept delivery' : delivery['status'] == 'Accepted' ? 'Mark picked up' : delivery['status'] == 'Picked up' ? 'Mark delivered' : 'Completed'),
                  )),
                ]),
              ),
            )),
        const SizedBox(height: 14),
        const Card(child: ListTile(leading: Icon(Icons.info_outline, color: Color(0xFFFF6B35)), title: Text('Demo delivery data'), subtitle: Text('Live delivery endpoints will connect here when available.'))),
      ],
    );
  }

  Widget _metric(String label, String value, IconData icon) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Icon(icon, color: const Color(0xFFFF6B35)), const SizedBox(height: 6), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11))]))));

  Widget _sectionTitle(String title, String? action, VoidCallback? onTap) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(children: [Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)), const Spacer(), if (action != null) TextButton(onPressed: onTap, child: Text(action))]));

  Future<void> _addMenuItem() async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final values = await showDialog<List<String>>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Add menu item'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Price'))]), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, [nameController.text.trim(), priceController.text.trim()]), child: const Text('Add'))]));
    nameController.dispose();
    priceController.dispose();
    if (values == null || values[0].isEmpty) return;
    setState(() => _menu.add({'name': values[0], 'price': double.tryParse(values[1]) ?? 0, 'available': true}));
  }

  Future<void> _logout() async {
    await ApiService().logout();
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
              */
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search restaurants or food...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => _setQuery(''),
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 22),

            if (normalizedQuery.isEmpty) ...[
              const Text(
                'Popular Searches',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    [
                      'Burger',
                      'Pizza',
                      'Sushi',
                      'Chicken',
                      'Noodles',
                      'Drinks',
                    ].map((item) {
                      return ActionChip(
                        label: Text(item),
                        avatar: const Icon(Icons.search, size: 17),
                        onPressed: () => _setQuery(item),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 24),
              const Text(
                'Find your next favorite meal',
                style: TextStyle(color: Colors.grey),
              ),
            ] else ...[
              Text(
                '${filteredResults.length} result${filteredResults.length == 1 ? '' : 's'} found',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filteredResults.isEmpty
                    ? const Center(
                        child: Text(
                          'No food or restaurant found.\nTry another search.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, height: 1.5),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filteredResults.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final result = filteredResults[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.all(8),
                            tileColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                result.imagePath,
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                              ),
                            ),
                            title: Text(
                              result.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(result.subtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RestaurantScreen(
                                  restaurantName: result.restaurantName,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SearchResult {
  final String title;
  final String subtitle;
  final String imagePath;
  final String restaurantName;

  const SearchResult({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.restaurantName,
  });
}

// ============================================================
// CART SCREEN
// ============================================================

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Future<void> _confirmClearCart(BuildContext context) async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('All items will be removed from your cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
            ),
            child: const Text('Clear cart'),
          ),
        ],
      ),
    );
    if (shouldClear == true) cartStore.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'My Cart',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                AnimatedBuilder(
                  animation: cartStore,
                  builder: (context, _) => cartStore.items.isEmpty
                      ? const SizedBox.shrink()
                      : TextButton.icon(
                          onPressed: () => _confirmClearCart(context),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Clear'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 25),
            const SizedBox(height: 18),
            Expanded(
              child: AnimatedBuilder(
                animation: cartStore,
                builder: (context, _) {
                  if (cartStore.items.isEmpty) {
                    return const Center(
                      child: Text(
                        'Your cart is empty.\nAdd something delicious to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, height: 1.5),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: cartStore.items.length,
                    itemBuilder: (context, index) {
                      final item = cartStore.items[index];
                      return CartItem(
                        name: item.name,
                        price: '\$${item.price.toStringAsFixed(2)}',
                        quantity: item.quantity,
                        imagePath: item.imagePath,
                        onIncrease: () => cartStore.increment(item),
                        onDecrease: () => cartStore.decrement(item),
                      );
                    },
                  );
                },
              ),
            ),
            const PromoCodeBox(),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: cartStore,
              builder: (context, _) => Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    PriceRow(
                      title: 'Subtotal',
                      value: '\$${cartStore.subtotal.toStringAsFixed(2)}',
                    ),
                    PriceRow(
                      title: 'Delivery',
                      value: '\$${cartStore.deliveryFee.toStringAsFixed(2)}',
                    ),
                    PriceRow(
                      title: 'Service fee',
                      value: '\$${cartStore.serviceFee.toStringAsFixed(2)}',
                    ),
                    if (cartStore.promoDiscount > 0)
                      PriceRow(
                        title: 'Promo ${cartStore.appliedPromo}',
                        value:
                            '-\$${cartStore.promoDiscount.toStringAsFixed(2)}',
                        color: Colors.green,
                      ),
                    const Divider(),
                    PriceRow(
                      title: 'Total',
                      value: '\$${cartStore.total.toStringAsFixed(2)}',
                      bold: true,
                    ),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: cartStore.items.isEmpty
                            ? null
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const CheckoutScreen(),
                                ),
                              ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B35),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        child: const Text(
                          'CHECKOUT',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PromoCodeBox extends StatefulWidget {
  const PromoCodeBox({super.key});

  @override
  State<PromoCodeBox> createState() => _PromoCodeBoxState();
}

class _PromoCodeBoxState extends State<PromoCodeBox> {
  final TextEditingController _controller = TextEditingController();
  String? _message;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final success = cartStore.applyPromo(_controller.text);
    setState(
      () => _message = success ? '10% discount applied' : 'Try code FOODGO10',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: cartStore,
      builder: (context, _) {
        if (cartStore.appliedPromo != null) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.local_offer, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${cartStore.appliedPromo} applied',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: cartStore.removePromo,
                  child: const Text('Remove'),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'Promo code',
                      prefixIcon: const Icon(Icons.local_offer_outlined),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _apply, child: const Text('Apply')),
              ],
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 5, left: 8),
                child: Text(
                  _message!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ============================================================
// CART ITEM
// ============================================================

class CartItem extends StatelessWidget {
  final String name;
  final String price;
  final int quantity;
  final String? imagePath;
  final VoidCallback? onIncrease;
  final VoidCallback? onDecrease;

  const CartItem({
    super.key,
    required this.name,
    required this.price,
    required this.quantity,
    this.imagePath,
    this.onIncrease,
    this.onDecrease,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8DD),
              borderRadius: BorderRadius.circular(14),
            ),
            child: imagePath != null
                ? Image.asset(imagePath!, fit: BoxFit.cover)
                : const Icon(Icons.fastfood, color: Color(0xFFFF6B35)),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),

                const SizedBox(height: 6),

                Text(
                  price,
                  style: const TextStyle(
                    color: Color(0xFFFF6B35),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          Row(
            children: [
              IconButton(
                onPressed: onDecrease,
                icon: const Icon(Icons.remove_circle_outline),
              ),

              Text(
                quantity.toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),

              IconButton(
                onPressed: onIncrease,
                icon: const Icon(Icons.add_circle),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CHECKOUT
// ============================================================

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _selectedPayment = 'cash';
  late final String _orderNumber;
  bool _paymentSubmitted = false;
  bool _orderCreated = false;

  @override
  void initState() {
    super.initState();
    _orderNumber =
        '#FG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
  }

  void _setPaymentMethod(String value) {
    setState(() {
      _selectedPayment = value;
      _paymentSubmitted = false;
    });
  }

  Future<void> _showReceipt(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: _selectedPayment == 'qr'
                          ? const Color(0xFFFFF3E0)
                          : const Color(0xFFE8F5E9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _selectedPayment == 'qr'
                          ? Icons.hourglass_top_rounded
                          : Icons.check_rounded,
                      color: _selectedPayment == 'qr'
                          ? Colors.orange
                          : Colors.green,
                      size: 34,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _selectedPayment == 'qr'
                        ? 'Order submitted'
                        : 'Order confirmed!',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text(
                    'Thanks for ordering, Se Reii',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        color: Color(0xFFFF6B35),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Order number',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              _orderNumber,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE8DD),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _selectedPayment == 'qr'
                              ? 'PAYMENT PENDING'
                              : 'CONFIRMED',
                          style: const TextStyle(
                            color: Color(0xFFFF6B35),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Your items',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 8),
                ...cartStore.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            item.imagePath,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${item.name}  x${item.quantity}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        Text(
                          '\$${item.total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 18),
                _ReceiptRow(
                  label: 'Subtotal',
                  value: '\$${cartStore.subtotal.toStringAsFixed(2)}',
                ),
                _ReceiptRow(
                  label: 'Delivery',
                  value: '\$${cartStore.deliveryFee.toStringAsFixed(2)}',
                ),
                _ReceiptRow(
                  label: 'Service fee',
                  value: '\$${cartStore.serviceFee.toStringAsFixed(2)}',
                ),
                if (cartStore.promoDiscount > 0)
                  _ReceiptRow(
                    label: 'Promo discount',
                    value: '-\$${cartStore.promoDiscount.toStringAsFixed(2)}',
                    color: Colors.green,
                  ),
                const Divider(height: 18),
                _ReceiptRow(
                  label: _selectedPayment == 'qr'
                      ? 'Order total'
                      : 'Total paid',
                  value: '\$${cartStore.total.toStringAsFixed(2)}',
                  bold: true,
                ),
                const SizedBox(height: 5),
                Text(
                  'Payment: ${_selectedPayment == 'qr'
                      ? 'QR Payment'
                      : _selectedPayment == 'card'
                      ? 'Credit / Debit Card'
                      : 'Cash on Delivery'}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                if (_selectedPayment == 'qr') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Payment is not verified yet. The order is saved as pending.',
                    style: TextStyle(
                      color: Colors.deepOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                const Text(
                  'Deliver to',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  '${addressStore.selectedAddress.label}: '
                  '${addressStore.selectedAddress.fullAddress}, '
                  '${addressStore.selectedAddress.city}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: const Text('View my order'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      if (!_orderCreated) _saveOrder();
      cartStore.clear();
      Navigator.pop(context);
    }
  }

  void _saveOrder() {
    if (_orderCreated || cartStore.items.isEmpty) return;
    final deliveryAddress = addressStore.selectedAddress;
    orderStore.addFromCart(
      orderNumber: _orderNumber,
      deliveryAddress:
          '${deliveryAddress.fullAddress}, ${deliveryAddress.city}',
      destinationLatitude: deliveryAddress.latitude,
      destinationLongitude: deliveryAddress.longitude,
      paymentPending: _selectedPayment == 'qr',
    );
    _orderCreated = true;
  }

  Future<void> _placeOrder() async {
    if (addressStore.selectedAddress.city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a delivery location first.')),
      );
      return;
    }
    if (_selectedPayment == 'qr' && !_paymentSubmitted) {
      setState(() => _paymentSubmitted = true);
    }
    if (mounted) await _showReceipt(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Checkout',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery Address',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    AnimatedBuilder(
                      animation: addressStore,
                      builder: (context, _) {
                        final address = addressStore.selectedAddress;
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              barrierColor: Colors.black54,
                              builder: (_) => const AddressPickerSheet(),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(15),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFEEE7),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: const Icon(
                                      Icons.location_on_outlined,
                                      color: Color(0xFFFF6B35),
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                address.label,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'CHANGE',
                                              style: TextStyle(
                                                color: Color(0xFFFF6B35),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${address.fullAddress}, ${address.city}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF77716F),
                                            fontSize: 13,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFF8C8582),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 25),

                    const Text(
                      'Payment Method',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      child: RadioGroup<String>(
                        groupValue: _selectedPayment,
                        onChanged: (value) {
                          if (value != null) {
                            _setPaymentMethod(value);
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Column(
                            children: [
                              RadioListTile(
                                value: 'cash',
                                title: Text('Cash on Delivery'),
                                secondary: Icon(Icons.money),
                              ),
                              RadioListTile(
                                value: 'card',
                                title: Text('Credit / Debit Card'),
                                secondary: Icon(Icons.credit_card),
                              ),
                              RadioListTile(
                                value: 'qr',
                                title: Text('QR Payment'),
                                secondary: Icon(Icons.qr_code),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (_selectedPayment == 'qr') ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Bakong KHQR',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '\$${cartStore.total.toStringAsFixed(2)} USD',
                              style: const TextStyle(
                                color: Color(0xFFFF6B35),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: const Color(0xFFECE8E5),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Image.asset(
                                'assets/images/QRCODE.png',
                                width: 230,
                                height: 322,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const SizedBox(
                                  width: 230,
                                  height: 220,
                                  child: Center(
                                    child: Text(
                                      'Could not load the ABA QR image.',
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Scan with ABA or another KHQR banking app',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Enter the exact cart total shown above in USD.',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'This is a static QR. Check incoming transactions in the '
                              'receiving ABA account; this app cannot detect the transfer.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (_paymentSubmitted)
                              Text(
                                'Order is awaiting payment confirmation. No delivery '
                                'will start until the receiver confirms the money arrived.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.deepOrange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    _selectedPayment == 'qr'
                        ? _paymentSubmitted
                              ? 'ORDER AWAITING CONFIRMATION'
                              : 'I HAVE SENT PAYMENT • WAITING CONFIRMATION'
                        : 'PLACE ORDER • \$${cartStore.total.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AddressPickerSheet extends StatefulWidget {
  const AddressPickerSheet({super.key});

  @override
  State<AddressPickerSheet> createState() => _AddressPickerSheetState();
}

class _AddressPickerSheetState extends State<AddressPickerSheet> {
  static const _cambodianAreas = [
    'Banteay Meanchey',
    'Battambang',
    'Kampong Cham',
    'Kampong Chhnang',
    'Kampong Speu',
    'Kampong Thom',
    'Kampot',
    'Kandal',
    'Kep',
    'Koh Kong',
    'Kratie',
    'Mondulkiri',
    'Oddar Meanchey',
    'Pailin',
    'Phnom Penh',
    'Preah Sihanouk',
    'Preah Vihear',
    'Prey Veng',
    'Pursat',
    'Ratanakiri',
    'Siem Reap',
    'Stung Treng',
    'Svay Rieng',
    'Takeo',
    'Tboung Khmum',
  ];

  final _searchController = TextEditingController();
  String _query = '';
  String? _error;
  bool _findingLocation = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _chooseArea(String area) {
    final record = addressStore.addAddress(
      'Delivery area',
      area,
      'Cambodia',
      selectAddress: true,
    );
    addressStore.select(record.id);
    Navigator.pop(context);
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _findingLocation = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationServiceDisabledException();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const ApiException('Location permission was denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw const ApiException(
          'Location permission is blocked. Enable it in your device settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final placemarks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final place = placemarks.firstOrNull;
      final addressParts =
          <String?>[
                place?.name,
                place?.street,
                place?.subLocality,
                place?.locality,
                place?.subAdministrativeArea,
                place?.administrativeArea,
                place?.postalCode,
              ]
              .whereType<String>()
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty);
      final readableAddress = addressParts.toSet().join(', ');
      final city =
          [
                place?.locality,
                place?.subAdministrativeArea,
                place?.administrativeArea,
                place?.country,
              ]
              .whereType<String>()
              .map((part) => part.trim())
              .firstWhere(
                (part) => part.isNotEmpty,
                orElse: () => 'Current location',
              );
      final address = addressStore.addAddress(
        'Current location',
        readableAddress.isEmpty
            ? '${position.latitude.toStringAsFixed(5)}, '
                  '${position.longitude.toStringAsFixed(5)}'
            : readableAddress,
        city,
        latitude: position.latitude,
        longitude: position.longitude,
        selectAddress: true,
      );
      if (!mounted) return;
      addressStore.select(address.id);
      Navigator.pop(context);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on LocationServiceDisabledException {
      if (mounted) {
        setState(() => _error = 'Turn on location services and try again.');
      }
    } on Exception {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not find your address. Try entering it manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _findingLocation = false);
    }
  }

  Future<void> _enterAddressManually() async {
    final labelController = TextEditingController(text: 'Delivery address');
    final addressController = TextEditingController();
    final cityController = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter delivery address'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Street, building, or landmark',
                ),
              ),
              TextField(
                controller: cityController,
                decoration: const InputDecoration(
                  labelText: 'City, province, or country',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final values = [
                labelController.text.trim(),
                addressController.text.trim(),
                cityController.text.trim(),
              ];
              if (values.any((value) => value.isEmpty)) return;
              Navigator.pop(dialogContext, values);
            },
            child: const Text('Use address'),
          ),
        ],
      ),
    );
    labelController.dispose();
    addressController.dispose();
    cityController.dispose();

    if (result == null || !mounted) return;
    final address = addressStore.addAddress(
      result[0],
      result[1],
      result[2],
      selectAddress: true,
    );
    addressStore.select(address.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filteredAreas = _cambodianAreas
        .where((area) => area.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Material(
          color: const Color(0xFFFAF9F8),
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9D5D2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Where to deliver?',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Choose a saved address or find a place',
                            style: TextStyle(
                              color: Color(0xFF77716F),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close location picker',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF514B48),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Search province or city',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFECE8E5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF6B35),
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: const Color(0xFFFFEEE7),
                  borderRadius: BorderRadius.circular(15),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(15),
                    onTap: _findingLocation ? null : _useCurrentLocation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.my_location,
                              color: Color(0xFFFF6B35),
                              size: 21,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Use current location',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'Pinpoint your delivery address',
                                  style: TextStyle(
                                    color: Color(0xFF77716F),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_findingLocation)
                            const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFFF6B35),
                              ),
                            )
                          else
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 15,
                              color: Color(0xFFFF6B35),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (addressStore.addresses.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 16, bottom: 7),
                    child: Text(
                      'SAVED ADDRESSES',
                      style: TextStyle(
                        color: Color(0xFF817A77),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 112,
                    child: ListView.separated(
                      itemCount: addressStore.addresses.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final address = addressStore.addresses[index];
                        final selected =
                            address.id == addressStore.selectedAddressId;
                        return Material(
                          color: selected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(13),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(13),
                            onTap: () {
                              addressStore.select(address.id);
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFFFFCBB6)
                                      : const Color(0xFFECE8E5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    address.latitude == null
                                        ? Icons.home_outlined
                                        : Icons.my_location,
                                    size: 19,
                                    color: const Color(0xFFFF6B35),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          address.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Text(
                                          '${address.fullAddress}, ${address.city}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFF77716F),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check_circle,
                                      size: 19,
                                      color: Color(0xFFFF6B35),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 5),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'CAMBODIA',
                          style: TextStyle(
                            color: Color(0xFF817A77),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '${filteredAreas.length} areas',
                        style: const TextStyle(
                          color: Color(0xFF8B8581),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filteredAreas.isEmpty
                      ? const Center(
                          child: Text(
                            'No matching area. Try another search.',
                            style: TextStyle(color: Color(0xFF77716F)),
                          ),
                        )
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: filteredAreas.length,
                          separatorBuilder: (_, _) => const Divider(
                            height: 1,
                            indent: 43,
                            color: Color(0xFFECE8E5),
                          ),
                          itemBuilder: (context, index) {
                            final area = filteredAreas[index];
                            return ListTile(
                              minVerticalPadding: 5,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.location_city_outlined,
                                  size: 18,
                                  color: Color(0xFF706965),
                                ),
                              ),
                              title: Text(
                                area,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Color(0xFF9B9490),
                              ),
                              onTap: () => _chooseArea(area),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _enterAddressManually,
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: const Text('Enter a full address'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF514B48),
                      backgroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      side: const BorderSide(color: Color(0xFFE5E0DD)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
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

// ============================================================
// ORDERS SCREEN
// ============================================================

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Orders',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: ['All', 'Active', 'Delivered', 'Cancelled'].map((
                  filter,
                ) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ChoiceChip(
                      label: Text(filter),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: deliveryTrackingService.currentUserId == null
                    ? null
                    : deliveryTrackingService.watchCustomerOrders(),
                builder: (context, liveOrders) => AnimatedBuilder(
                  animation: orderStore,
                  builder: (context, _) {
                    final allOrders =
                        liveOrders.data?.docs
                            .map(OrderRecord.fromDocument)
                            .toList() ??
                        orderStore.orders;
                    final visibleOrders = allOrders.where((order) {
                      if (_filter == 'Active') {
                        return order.status != 'Delivered' &&
                            order.status != 'Cancelled';
                      }
                      if (_filter == 'Delivered') {
                        return order.status == 'Delivered';
                      }
                      if (_filter == 'Cancelled') {
                        return order.status == 'Cancelled';
                      }
                      return true;
                    }).toList();
                    if (liveOrders.hasError && allOrders.isEmpty) {
                      return Center(
                        child: Text(
                          'Unable to load orders: ${liveOrders.error}',
                        ),
                      );
                    }
                    if (visibleOrders.isEmpty) {
                      return const Center(
                        child: Text(
                          'Your orders will appear here.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: visibleOrders.length,
                      itemBuilder: (context, index) {
                        final order = visibleOrders[index];
                        return OrderCard(
                          orderNumber: order.orderNumber,
                          restaurant: order.restaurantName,
                          total: '\$${order.total.toStringAsFixed(2)}',
                          status: order.status,
                          active:
                              order.status != 'Delivered' &&
                              order.status != 'Cancelled',
                          imagePath: order.imagePath,
                          itemCount: order.itemCount,
                          onTrack: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  DeliveryTrackingScreen(order: order),
                            ),
                          ),
                          onDetails: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => OrderDetailsSheet(order: order),
                          ),
                          onCancel:
                              order.status == 'Preparing' ||
                                  order.status == 'Awaiting payment'
                              ? () async {
                                  final shouldCancel = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Cancel order?'),
                                      content: const Text(
                                        'This delivery will be cancelled.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext,
                                            false,
                                          ),
                                          child: const Text('Keep order'),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                            dialogContext,
                                            true,
                                          ),
                                          child: const Text('Cancel order'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (shouldCancel == true) {
                                    if (order.trackingId == null) {
                                      orderStore.cancel(order);
                                    } else {
                                      try {
                                        await deliveryTrackingService
                                            .cancelOrder(order.trackingId!);
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
                                          );
                                        }
                                      }
                                    }
                                  }
                                }
                              : null,
                          onRate: order.status == 'Delivered'
                              ? () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Rate this order'),
                                      content: const Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('How was your experience?'),
                                          SizedBox(height: 12),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.star,
                                                color: Colors.amber,
                                              ),
                                              Icon(
                                                Icons.star,
                                                color: Colors.amber,
                                              ),
                                              Icon(
                                                Icons.star,
                                                color: Colors.amber,
                                              ),
                                              Icon(
                                                Icons.star,
                                                color: Colors.amber,
                                              ),
                                              Icon(
                                                Icons.star_border,
                                                color: Colors.amber,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Later'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Submit'),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// ORDER CARD
// ============================================================

class OrderCard extends StatelessWidget {
  final String orderNumber;
  final String restaurant;
  final String total;
  final String status;
  final bool active;
  final String? imagePath;
  final int? itemCount;
  final VoidCallback? onTrack;
  final VoidCallback? onCancel;
  final VoidCallback? onRate;
  final VoidCallback? onDetails;

  const OrderCard({
    super.key,
    required this.orderNumber,
    required this.restaurant,
    required this.total,
    required this.status,
    required this.active,
    this.imagePath,
    this.itemCount,
    this.onTrack,
    this.onCancel,
    this.onRate,
    this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFFFE8DD),
                backgroundImage: imagePath == null
                    ? null
                    : AssetImage(imagePath!),
                child: imagePath == null
                    ? const Icon(Icons.restaurant, color: Color(0xFFFF6B35))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orderNumber,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    if (itemCount != null)
                      Text(
                        '$itemCount item${itemCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Text(total, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 25),
          _OrderTimeline(status: status),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                active ? Icons.delivery_dining : Icons.check_circle,
                color: active ? const Color(0xFFFF6B35) : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                status,
                style: TextStyle(
                  color: active ? const Color(0xFFFF6B35) : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (active)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: onDetails,
                      child: const Text('Details'),
                    ),
                    TextButton(onPressed: onTrack, child: const Text('Track')),
                  ],
                )
              else if (onRate != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: onDetails,
                      child: const Text('Details'),
                    ),
                    TextButton(onPressed: onRate, child: const Text('Rate')),
                  ],
                )
              else
                const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }
}

class DeliveryTrackingScreen extends StatefulWidget {
  final OrderRecord order;
  final String? role;

  const DeliveryTrackingScreen({super.key, required this.order, this.role});

  @override
  State<DeliveryTrackingScreen> createState() => _DeliveryTrackingScreenState();
}

class _DeliveryTrackingScreenState extends State<DeliveryTrackingScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  LatLng? _lastCenteredPoint;
  String? _locationError;
  bool _sharingLocation = false;

  @override
  void initState() {
    super.initState();
    if (widget.role == 'seller' || widget.role == 'driver') {
      _startLocationSharing();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startLocationSharing() async {
    if (widget.order.trackingId == null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationServiceDisabledException();
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const ApiException(
          'Allow location access to share live tracking.',
        );
      }
      if (!mounted) return;
      setState(() {
        _sharingLocation = true;
        _locationError = null;
      });
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen(
            (position) {
              unawaited(
                deliveryTrackingService
                    .updateLocation(
                      widget.order.trackingId!,
                      GeoPoint(position.latitude, position.longitude),
                      fromSeller: widget.role == 'seller',
                    )
                    .catchError((Object error) {
                      if (mounted) {
                        setState(() => _locationError = error.toString());
                      }
                    }),
              );
            },
            onError: (Object error) {
              if (mounted) setState(() => _locationError = error.toString());
            },
          );
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _sharingLocation = false;
          _locationError = error is ApiException
              ? error.message
              : 'Unable to access this device location.';
        });
      }
    }
  }

  LatLng? _point(dynamic value) {
    if (value is! GeoPoint) return null;
    return LatLng(value.latitude, value.longitude);
  }

  Widget _trackingContent(Map<String, dynamic> data) {
    final courier = _point(data['courierLocation']);
    final seller = _point(data['sellerLocation']);
    final destination =
        _point(data['destination']) ??
        (widget.order.destinationLatitude == null ||
                widget.order.destinationLongitude == null
            ? null
            : LatLng(
                widget.order.destinationLatitude!,
                widget.order.destinationLongitude!,
              ));
    final points = [seller, courier, destination].whereType<LatLng>().toList();
    final center = points.isNotEmpty
        ? points[points.length ~/ 2]
        : const LatLng(11.5564, 104.9282);
    if (_lastCenteredPoint != center) {
      _lastCenteredPoint = center;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(center, 14.5);
      });
    }
    final status = data['status'] as String? ?? widget.order.status;
    final markers = <Marker>[
      if (seller != null)
        Marker(
          point: seller,
          width: 110,
          height: 62,
          child: const _MapPin(
            label: 'Restaurant',
            icon: Icons.restaurant,
            color: Color(0xFFFF6B35),
          ),
        ),
      if (destination != null)
        Marker(
          point: destination,
          width: 100,
          height: 62,
          child: const _MapPin(
            label: 'Customer',
            icon: Icons.home,
            color: Colors.green,
          ),
        ),
      if (courier != null)
        Marker(
          point: courier,
          width: 112,
          height: 72,
          child: _MapPin(
            label: (data['driverName'] as String?)?.isNotEmpty == true
                ? data['driverName'] as String
                : 'Courier',
            icon: Icons.delivery_dining,
            color: const Color(0xFFFF6B35),
          ),
        ),
    ];

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(initialCenter: center, initialZoom: 14.5),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.ecommerce_app',
                  ),
                  if (markers.isNotEmpty) MarkerLayer(markers: markers),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution('OpenStreetMap contributors'),
                    ],
                  ),
                ],
              ),
              if (markers.isEmpty)
                const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Waiting for seller or courier location'),
                    ),
                  ),
                ),
              Positioned(
                right: 16,
                top: 16,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'zoom-in',
                      onPressed: () => _mapController.move(center, 15.5),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      child: const Icon(Icons.add),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'recenter',
                      onPressed: () => _mapController.move(center, 14.5),
                      backgroundColor: const Color(0xFFFF6B35),
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'zoom-out',
                      onPressed: () => _mapController.move(center, 13.5),
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      child: const Icon(Icons.remove),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.order.restaurantName} · ${widget.order.orderNumber}',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'Live GPS',
                    style: TextStyle(
                      color: Color(0xFFFF6B35),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                destination == null
                    ? 'Set this address using your current location to show the customer pin.'
                    : courier == null
                    ? 'Waiting for the courier to share location.'
                    : 'Courier location updates appear here as the driver moves.',
                style: const TextStyle(color: Colors.grey),
              ),
              if (_sharingLocation)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Sharing this device location',
                    style: TextStyle(color: Colors.green),
                  ),
                ),
              if (_locationError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _locationError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (widget.role == 'driver' && status == 'On the way')
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => deliveryTrackingService.markDelivered(
                      widget.order.trackingId!,
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('Mark delivered'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackingId = widget.order.trackingId;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Track delivery',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: trackingId == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Live tracking is available for orders placed while signed in.',
                ),
              ),
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: deliveryTrackingService.watchOrder(trackingId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Unable to load live tracking: ${snapshot.error}',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!.data();
                if (data == null) {
                  return const Center(
                    child: Text('This order is no longer available.'),
                  );
                }
                return _trackingContent(data);
              },
            ),
    );
  }
}

class _MapPin extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _MapPin({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        Icon(icon, color: color, size: 30),
      ],
    );
  }
}

class OrderDetailsSheet extends StatelessWidget {
  final OrderRecord order;

  const OrderDetailsSheet({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Order Details',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0EA),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              order.orderNumber,
              style: const TextStyle(
                color: Color(0xFFFF6B35),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFE8DD),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.restaurant_rounded,
                  color: Color(0xFFFF6B35),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.restaurantName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${order.itemCount} item${order.itemCount == 1 ? '' : 's'}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  order.status,
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Delivery Address',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            order.deliveryAddress,
            style: const TextStyle(color: Colors.grey, height: 1.4),
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Subtotal', style: TextStyle(color: Colors.grey)),
              const Spacer(),
              Text('\$${order.total.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Text('Delivery', style: TextStyle(color: Colors.grey)),
              Spacer(),
              Text('\$0.00'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              Text('Service fee', style: TextStyle(color: Colors.grey)),
              Spacer(),
              Text('\$0.00'),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '\$${order.total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DeliveryTrackingScreen(order: order),
                  ),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Track order'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderTimeline extends StatelessWidget {
  final String status;

  const _OrderTimeline({required this.status});

  @override
  Widget build(BuildContext context) {
    final activeStep = status == 'Delivered'
        ? 2
        : status == 'On the way'
        ? 1
        : 0;
    const labels = ['Preparing', 'On the way', 'Delivered'];
    return Row(
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: index <= activeStep
                        ? const Color(0xFFFF6B35)
                        : const Color(0xFFE0E0E0),
                    shape: BoxShape.circle,
                  ),
                  child: index <= activeStep
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
                const SizedBox(height: 5),
                Text(
                  labels[index],
                  style: TextStyle(
                    fontSize: 10,
                    color: index <= activeStep ? Colors.black87 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          if (index < labels.length - 1)
            Expanded(
              child: Container(
                height: 2,
                color: index < activeStep
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFFE0E0E0),
              ),
            ),
        ],
      ],
    );
  }
}

// ============================================================
// PROFILE
// ============================================================

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: AnimatedBuilder(
        animation: notificationStore,
        builder: (context, _) {
          if (notificationStore.items.isEmpty) {
            return const Center(
              child: Text(
                'No notifications yet.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: notificationStore.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = notificationStore.items[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE8DD),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        item.icon,
                        color: const Color(0xFFFF6B35),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.detail,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.time,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.unread)
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFF6B35),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: notificationStore.markAllRead,
        backgroundColor: const Color(0xFFFF6B35),
        child: const Icon(Icons.done_all),
      ),
    );
  }
}

class AddressManagementScreen extends StatefulWidget {
  const AddressManagementScreen({super.key});

  @override
  State<AddressManagementScreen> createState() =>
      _AddressManagementScreenState();
}

class _AddressManagementScreenState extends State<AddressManagementScreen> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();

  void _showForm({AddressRecord? record}) {
    if (record != null) {
      _labelController.text = record.label;
      _addressController.text = record.fullAddress;
      _cityController.text = record.city;
    } else {
      _labelController.clear();
      _addressController.clear();
      _cityController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(record == null ? 'Add address' : 'Edit address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _labelController,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Full address'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(labelText: 'City'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final label = _labelController.text.trim();
              final address = _addressController.text.trim();
              final city = _cityController.text.trim();
              if (label.isEmpty || address.isEmpty || city.isEmpty) return;

              if (record == null) {
                addressStore.addAddress(label, address, city);
              } else {
                addressStore.updateAddress(record.id, label, address, city);
              }
              Navigator.pop(context);
            },
            child: Text(record == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Addresses')),
      body: AnimatedBuilder(
        animation: addressStore,
        builder: (context, _) {
          if (addressStore.addresses.isEmpty) {
            return const Center(
              child: Text(
                'No saved addresses yet.',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: addressStore.addresses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = addressStore.addresses[index];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, color: Color(0xFFFF6B35)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (item.isDefault) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFE8DD),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Default',
                                    style: TextStyle(
                                      color: Color(0xFFFF6B35),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.fullAddress,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.city,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () =>
                                    addressStore.setDefault(item.id),
                                child: const Text('Set default'),
                              ),
                              TextButton(
                                onPressed: () => _showForm(record: item),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    addressStore.deleteAddress(item.id),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: const Color(0xFFFF6B35),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Future<String?> _requestRestaurantName(String initialValue) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assign restaurant'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Restaurant name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty == true ? null : result?.trim();
  }

  Future<void> _assignRole(
    String userId,
    String role,
    Map<String, dynamic> profile,
  ) async {
    String? restaurantName;
    if (role == 'seller') {
      restaurantName = await _requestRestaurantName(
        profile['restaurantName'] as String? ?? '',
      );
      if (restaurantName == null) return;
    }

    try {
      await ApiService().updateUserRole(
        userId,
        role,
        restaurantName: restaurantName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account updated to $role.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account access')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: ApiService().watchProfiles(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Unable to load accounts: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No accounts found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text(
                'Accounts',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Assign customers to the seller or driver workspaces.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 14),
              ...snapshot.data!.docs.map((document) {
                final profile = document.data();
                final role = profile['role'] as String? ?? 'customer';
                final isSelf = document.id == ApiService.user?['uid'];
                final restaurantName = profile['restaurantName'] as String?;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      role == 'seller'
                          ? Icons.storefront_outlined
                          : role == 'driver'
                          ? Icons.delivery_dining_outlined
                          : role == 'admin'
                          ? Icons.admin_panel_settings_outlined
                          : Icons.person_outline,
                      color: const Color(0xFFFF6B35),
                    ),
                    title: Text(profile['name'] as String? ?? 'Unnamed account'),
                    subtitle: Text(
                      '${profile['email'] ?? ''} · $role'
                      '${restaurantName == null ? '' : ' · $restaurantName'}',
                    ),
                    trailing: isSelf || role == 'admin'
                        ? const Icon(Icons.lock_outline, color: Colors.grey)
                        : PopupMenuButton<String>(
                            tooltip: 'Assign account role',
                            onSelected: (nextRole) => _assignRole(
                              document.id,
                              nextRole,
                              profile,
                            ),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'customer',
                                child: Text('Customer'),
                              ),
                              PopupMenuItem(
                                value: 'seller',
                                child: Text('Seller'),
                              ),
                              PopupMenuItem(
                                value: 'driver',
                                child: Text('Driver'),
                              ),
                            ],
                          ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  late Future<Map<String, dynamic>> _profile;

  @override
  void initState() {
    super.initState();
    _profile = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() {
    if (ApiService.user != null) return Future.value(ApiService.user!);
    return _api.profile();
  }

  Future<void> _logout() async {
    try {
      await _api.logout();
    } catch (_) {
      ApiService.token = null;
      ApiService.user = null;
    }
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _editProfile() async {
    final profile = ApiService.user ?? const <String, dynamic>{};
    final nameController = TextEditingController(
      text: profile['name'] as String? ?? '',
    );
    final emailController = TextEditingController(
      text: profile['email'] as String? ?? '',
    );
    final phoneController = TextEditingController(
      text: profile['phone'] as String? ?? '',
    );
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, [
              nameController.text.trim(),
              emailController.text.trim(),
              phoneController.text.trim(),
            ]),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    if (values == null || values.any((value) => value.isEmpty) || !mounted) {
      return;
    }
    try {
      final updated = await _api.updateProfile(
        name: values[0],
        email: values[1],
        phone: values[2],
      );
      if (mounted) {
        setState(() => _profile = Future.value(updated));
        final message = updated['emailVerificationPending'] == true
            ? 'Profile updated. Confirm the link sent to your new email.'
            : 'Profile updated.';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _deleteProfile() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await _api.deleteAccount();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profile,
      builder: (context, snapshot) {
        final profile =
            snapshot.data ?? ApiService.user ?? const <String, dynamic>{};
        final name = profile['name'] as String? ?? 'FoodGo customer';
        final email = profile['email'] as String? ?? 'Not signed in';
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const SizedBox(height: 15),
                const CircleAvatar(
                  radius: 48,
                  backgroundColor: Color(0xFFFFE8DD),
                  child: Icon(Icons.person, size: 55, color: Color(0xFFFF6B35)),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(email, style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 30),
                ProfileOption(
                  icon: Icons.person_outline,
                  title: 'Edit Profile',
                  onTap: _editProfile,
                ),
                ProfileOption(
                  icon: Icons.location_on_outlined,
                  title: 'My Addresses',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddressManagementScreen(),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: favoriteStore,
                  builder: (context, _) => ProfileOption(
                    icon: Icons.favorite_border,
                    title: 'Favorites (${favoriteStore.restaurants.length})',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Your favorite restaurants are saved.'),
                      ),
                    ),
                  ),
                ),
                ProfileOption(
                  icon: Icons.payment,
                  title: 'Payment Methods',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Card management is available in the checkout flow.',
                      ),
                    ),
                  ),
                ),
                ProfileOption(
                  icon: Icons.notifications_none,
                  title: 'Notifications',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                ),
                ProfileOption(
                  icon: Icons.dashboard_customize,
                  title: 'Admin Dashboard',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminDashboardScreen(),
                    ),
                  ),
                ),
                ProfileOption(
                  icon: Icons.help_outline,
                  title: 'Help & Support',
                  onTap: () {},
                ),
                ProfileOption(
                  icon: Icons.settings_outlined,
                  title: 'Settings',
                  onTap: () {},
                ),
                ProfileOption(
                  icon: Icons.logout,
                  title: 'Logout',
                  onTap: _logout,
                ),
                ProfileOption(
                  icon: Icons.delete_outline,
                  title: 'Delete account',
                  onTap: _deleteProfile,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// PROFILE OPTION
// ============================================================

class ProfileOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const ProfileOption({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: const Color(0xFFFF6B35)),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}

// ============================================================
// SECTION TITLE
// ============================================================

class SectionTitle extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback? onTap;

  const SectionTitle({
    super.key,
    required this.title,
    required this.action,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),

        const Spacer(),

        GestureDetector(
          onTap: onTap,
          child: Text(
            action,
            style: const TextStyle(
              color: Color(0xFFFF6B35),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PRICE ROW
// ============================================================

class PriceRow extends StatelessWidget {
  final String title;
  final String value;
  final bool bold;
  final Color? color;

  const PriceRow({
    super.key,
    required this.title,
    required this.value,
    this.bold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 17 : 14,
            ),
          ),

          const Spacer(),

          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 17 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  const _ReceiptRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color ?? (bold ? Colors.black : Colors.grey),
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 16 : 12,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontSize: bold ? 16 : 12,
            ),
          ),
        ],
      ),
    );
  }
}

class OrderRecord {
  final String orderNumber;
  final String restaurantName;
  final String deliveryAddress;
  final String imagePath;
  final int itemCount;
  final double total;
  final DateTime createdAt;
  final double? destinationLatitude;
  final double? destinationLongitude;
  String? trackingId;
  String? trackingError;
  String status;

  OrderRecord({
    required this.orderNumber,
    required this.restaurantName,
    required this.deliveryAddress,
    required this.imagePath,
    required this.itemCount,
    required this.total,
    required this.createdAt,
    this.destinationLatitude,
    this.destinationLongitude,
    this.trackingId,
    this.status = 'Preparing',
  });

  factory OrderRecord.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final destination = data['destination'];
    final createdAt = data['createdAt'];
    return OrderRecord(
      orderNumber: data['orderNumber'] as String? ?? document.id,
      restaurantName: data['restaurantName'] as String? ?? 'Restaurant',
      deliveryAddress: data['deliveryAddress'] as String? ?? '',
      imagePath: data['imagePath'] as String? ?? '',
      itemCount: (data['itemCount'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toDouble() ?? 0,
      createdAt: createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
      destinationLatitude: destination is GeoPoint
          ? destination.latitude
          : null,
      destinationLongitude: destination is GeoPoint
          ? destination.longitude
          : null,
      trackingId: document.id,
      status: data['status'] as String? ?? 'Preparing',
    );
  }
}

class OrderStore extends ChangeNotifier {
  final List<OrderRecord> orders = [];

  void cancel(OrderRecord order) {
    orders.remove(order);
    notifyListeners();
  }

  void addFromCart({
    required String orderNumber,
    required String deliveryAddress,
    double? destinationLatitude,
    double? destinationLongitude,
    bool paymentPending = false,
  }) {
    if (cartStore.items.isEmpty) return;
    final now = DateTime.now();
    final order = OrderRecord(
      orderNumber: orderNumber,
      restaurantName: cartStore.items.first.restaurantName,
      deliveryAddress: deliveryAddress,
      imagePath: cartStore.items.first.imagePath,
      itemCount: cartStore.items.fold(0, (total, item) => total + item.quantity),
      total: cartStore.total,
      createdAt: now,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
      status: paymentPending ? 'Awaiting payment' : 'Preparing',
    );
    orders.insert(0, order);
    notifyListeners();
    unawaited(
      deliveryTrackingService
          .createOrder(
            orderNumber: order.orderNumber,
            restaurantName: order.restaurantName,
            deliveryAddress: order.deliveryAddress,
            total: order.total,
            itemCount: order.itemCount,
            imagePath: order.imagePath,
            status: order.status,
            destinationLatitude: destinationLatitude,
            destinationLongitude: destinationLongitude,
          )
          .then((trackingId) {
            order.trackingId = trackingId;
            notifyListeners();
          })
          .catchError((Object error) {
            order.trackingError = error.toString();
            notifyListeners();
          }),
    );
  }
}

final OrderStore orderStore = OrderStore();

class FavoriteStore extends ChangeNotifier {
  final Set<String> restaurants = {};

  bool contains(String name) => restaurants.contains(name);

  void toggle(String name) {
    if (!restaurants.add(name)) restaurants.remove(name);
    notifyListeners();
  }
}

final FavoriteStore favoriteStore = FavoriteStore();
