# ecommerce_app

A new Flutter project.

## Live Delivery Tracking

Tracking uses Firestore for shared order and GPS updates, Geolocator for device
locations, and OpenStreetMap tiles. No map API key is required.

1. Deploy the checked-in Firestore rules with `firebase deploy --only firestore:rules`.
2. Create a normal account in the app. In Firebase Console, change that user's
	`/users/{uid}` profile `role` to `admin` once, then sign in again. This
	bootstrap is required because an admin must not be self-assigned by public
	signup.
3. In Admin Dashboard, assign other accounts the `seller` or `driver` role.
	Sellers must also receive a `restaurantName` that exactly matches the
	restaurant on customer orders. Public registration always creates customers.
4. Customers sign in and choose **Use current location** for the delivery
	address. Sellers mark an order **Ready**; drivers accept it and open its live
	map. The seller and driver must keep that map screen open to share foreground
	GPS. Drivers can mark the order delivered from the map.

Background location sharing and turn-by-turn route/ETA calculation are not
included. OpenStreetMap's public tile service is suitable for development; use
a tile provider whose terms and capacity fit production traffic.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
