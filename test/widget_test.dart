import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ecommerce_app/main.dart';

void main() {
  testWidgets('FoodGo splash and home screen render', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FoodDeliveryApp());

    expect(find.text('FoodGo'), findsOneWidget);
    expect(find.text('Delicious food, delivered fast.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue as guest'));
    await tester.tap(find.text('Continue as guest'));
    await tester.pumpAndSettle();

    expect(find.text('What are you craving?'), findsOneWidget);
    expect(find.text('Burger House'), findsOneWidget);
  });

  testWidgets('address picker searches and selects a Cambodian province', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AddressPickerSheet())),
    );

    await tester.enterText(find.byType(TextField), 'Siem Reap');
    await tester.pump();
    expect(find.text('Siem Reap'), findsNWidgets(2));

    await tester.tap(find.byType(ListTile).last);
    await tester.pumpAndSettle();

    expect(addressStore.selectedAddress.fullAddress, 'Siem Reap');
    expect(addressStore.selectedAddress.city, 'Cambodia');
    addressStore.deleteAddress(addressStore.selectedAddress.id);
    addressStore.select('home');
  });

  test(
    'static QR payment orders remain pending until receiver confirmation',
    () {
      cartStore.addItem(
        name: 'Test meal',
        restaurantName: 'Test restaurant',
        price: '\$5.00',
        imagePath: 'assets/images/burger house.webp',
      );
      orderStore.addFromCart(
        orderNumber: '#FG-TEST',
        deliveryAddress: 'Phnom Penh, Cambodia',
        paymentPending: true,
      );

      expect(orderStore.orders.first.status, 'Awaiting payment');
      expect(orderStore.orders.first.total, 6.75);

      orderStore.cancel(orderStore.orders.first);
      cartStore.clear();
    },
  );

  testWidgets('checkout QR content scrolls on a phone-sized viewport', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: CheckoutScreen()));
    await tester.tap(find.text('QR Payment'));
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer and seller can access the driver workspace', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MainNavigation(role: 'customer')));
    expect(find.text('Deliveries'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: MainNavigation(role: 'seller')));
    expect(find.text('Store'), findsOneWidget);
    expect(find.text('Deliveries'), findsOneWidget);
  });
}
