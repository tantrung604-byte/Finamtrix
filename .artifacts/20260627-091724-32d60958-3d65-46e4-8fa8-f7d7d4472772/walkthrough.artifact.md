# Macro Data Migration and Organic Orders Integration Walkthrough

I have successfully migrated the Macro data sources to WIFEED, integrated real-time World Gold prices, synchronized the Home screen, and enhanced the Micro tab with "Organic Orders" logic.

## Accomplishments

### 1. WIFEED API Integration
- **Interest Rates**: Migrated `DepositRateService` to WIFEED. It now tracks group-based averages (SOBs, Major Private, Others).
- **CPI Data**: Implemented `CpiService` for real-time Consumer Price Index history.
- **Settings**: Updated the Profile screen to manage the official WIFEED API key.

### 2. World Gold Price (XAU/USD)
- Updated `GoldPriceService` to support domestic (SJC) and international (XAU/USD) prices.
- Integrated real-time data from `vang.today`.

### 3. Home Screen Synchronization
- Converted `HomeScreen` to a `StatefulWidget` for dynamic updates.
- Synchronized "Thị trường hôm nay" tickers with real-time services.
- Real historical trend lines (sparklines) are now generated from database history.

### 4. Micro Tab: Organic Orders Logic
- **Business Logic**: Updated `ForecastService` to distinguish between "Ad-driven Orders" (configured via channels) and "Organic Orders" (orders needed to reach revenue target not covered by Ads).
- **UI Enhancement**: Added a new step in the "Tính Ngược Phễu" section to explicitly show **Đơn hàng tự nhiên** and **Tổng đơn cần đạt**. This clarifies why total orders may differ from the ad-funnel calculation.

### 5. UI Enhancements & Fixes
- **USD Display**: Updated both Home and Macro screens to show both **Buy (Transfer)** and **Sell** rates for USD.
- **Real-time Updates**: Fixed logic issues that prevented charts and metrics from updating with real data. Added a `RefreshIndicator` for manual updates.

### 6. Infrastructure & Build
- Upgraded SQLite database to **Version 5**.
- **Release Build**: Successfully built the production APK with all new features and fixes.

## Verification Results

### Automated Tests
- **Macro Logic**: `test/macro_migration_test.dart` verifies WIFEED parsing.
- **Database**: `test/db_migration_test.dart` confirms v5 schema upgrade.
- **Build**: `flutter build apk --release` completed successfully.

### Manual Verification
- Verified the new funnel steps in the Micro tab: "Reach" -> "Click" -> "Đơn hàng chạy Ads" -> "Đơn hàng tự nhiên" -> "Tổng đơn".
- Confirmed that "Đơn hàng tự nhiên" only appears when there is a gap between channel-configured revenue and the total target revenue.

## Deliverables
- **Release APK**: [app-release.apk](file:///C:/Users/tantr/.gemini/antigravity-ide/scratch/finmatrix_flutter/build/app/outputs/flutter-apk/app-release.apk) (56.3MB)

## Key Files Modified
- [database_helper.dart](file:///C:/Users/tantr/.gemini/antigravity-ide/scratch/finmatrix_flutter/lib/services/database_helper.dart)
- [forecast_service.dart](file:///C:/Users/tantr/.gemini/antigravity-ide/scratch/finmatrix_flutter/lib/services/forecast_service.dart)
- [micro_screen.dart](file:///C:/Users/tantr/.gemini/antigravity-ide/scratch/finmatrix_flutter/lib/screens/micro_screen.dart)
- [home_screen.dart](file:///C:/Users/tantr/.gemini/antigravity-ide/scratch/finmatrix_flutter/lib/screens/home_screen.dart)
- [macro_screen.dart](file:///C:/Users/tantr/.gemini/antigravity-ide/scratch/finmatrix_flutter/lib/screens/macro_screen.dart)
