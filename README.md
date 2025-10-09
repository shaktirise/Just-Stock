# JustStock Mobile

Flutter client for the JustStock trading community. The app now targets the Render deployment at `https://backend-server-11f5.onrender.com/api`, wiring the latest email/password authentication, referral hierarchy, and wallet flows.

## Requirements

- Flutter 3.19+ (project uses `sdk: ^3.9.0`)
- Dart 3.9+
- Android/iOS device or emulator
- Optional Razorpay credentials for test checkout

Install dependencies:

```bash
flutter pub get
```

Run the app:

```bash
flutter run
```

## Configuration

`ApiConfig` reads the base URL from `API_BASE_URL` at build time. The default value already points to the Render environment, but you can override it easily:

```bash
flutter run --dart-define=API_BASE_URL=https://backend-server-11f5.onrender.com
```

Authenticated requests hit these endpoints (all relative to `/api`):

- `POST /auth/signup`
- `POST /auth/login`
- `POST /auth/refresh-token`
- `POST /auth/logout`
- `GET /auth/me`, `PUT /auth/me`
- `GET /auth/referrals`, `/auth/referrals/tree`, `/auth/referrals/earnings`, `/auth/referrals/config`
- `GET /wallet/balance`
- `POST /wallet/topups/create-order`
- `POST /wallet/topups/verify`
- `POST /wallet/debit`

Access tokens stay in SharedPreferences, refresh tokens in `flutter_secure_storage`, and `SessionService` auto-refreshes whenever an access token is close to expiring.

## Feature Highlights

- Email/password signup & login with clear validation and backend error surfacing.
- Secure token storage plus automatic refresh and `/auth/logout` integration.
- Dashboard card exposing wallet balance, referral code/link, quick navigation, and share actions powered by `share_plus`.
- Profile page mirrors wallet/referral data, allows sharing, and renders the MLM configuration (minimum activation/top-up, GST, and per-level percentages).
- Referral suite: list, tree, and earnings screens that call the new `/auth/referrals/*` endpoints with friendly empty states.
- Wallet flow rewritten to follow the new `/wallet/topups` and `/wallet/debit` contracts, including GST-aware debits and Razorpay verification payloads.

## Manual Test Flow

1. **Sign up** with an email, password, and (optionally) referral code → ensure JWT + refresh tokens are stored.
2. **Log out** (profile screen) and **log back in** via email/password.
3. On the **Home** referral card, try the quick actions:
   - Share link (verifies `share_plus` integration).
   - Referral list/tree/earnings (each should render server data or empty copy).
4. On the **Profile** page, pull to refresh → confirm `/auth/me` and `/auth/referrals/config` populate the wallet balance, referral counts, and MLM configuration.
5. **Add funds** (₹1000+ as required) → complete Razorpay test checkout → verify balance refresh and success snackbar.
6. **Debit** the wallet → snackbar should show total, base amount, and GST breakdown from `/wallet/debit`.
7. Trigger a token expiry scenario (or manually clear the refresh token) → ensure the next guarded call logs the user out and clears storage.

## Notes

- “Forgot password?” remains a placeholder until the backend exposes a reset endpoint.
- Referral codes are uppercased before submission; share buttons fall back to the code when a share link is not yet issued.
- All network failures bubble up through snackbars so QA can see actionable reasons without digging through logs.
