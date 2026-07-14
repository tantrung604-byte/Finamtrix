# Expand Industry Trends and Prioritize Real Data

The goal is to remove visible "FastMoss" branding from the Industry Trends (Micro) tab while ensuring that the system primarily fetches and displays **real data** (30 items) from the FastMoss Open API. Seed data will only remain as a fallback.

## Proposed Changes

### Industry Trends UI

#### [micro_screen.dart](file:///C:/Users/tantr/.gemini/antigravity-ide/scratch/finmatrix_flutter/lib/screens/micro_screen.dart)

- Remove "FastMoss" from titles, descriptions, and loading states.
- Update loops to display up to 30 items.

```diff
-                '🔥 Xu hướng ngành hàng (FastMoss)',
+                '🔥 Xu hướng ngành hàng',
...
-          'Top sản phẩm TikTok Shop đang bán chạy nhất trong ngành "$_selectedCategory"',
+          'Top 30 sản phẩm TikTok Shop đang bán chạy nhất trong ngành "$_selectedCategory"',
...
-                    ? 'Đang tải dữ liệu FastMoss…'
+                    ? 'Đang tải dữ liệu thị trường…'
...
-                    for (int i = 0; i < _fastmossTrends.length && i < 20; i++) ...[
+                    for (int i = 0; i < _fastmossTrends.length && i < 30; i++) ...[
```

---

### Data Services

#### [fastmoss_service.dart](file:///C:/Users/tantr/.gemini/antigravity-ide/scratch/finmatrix_flutter/lib/services/fastmoss_service.dart)

- **Prioritize Real Data**: Ensure `pagesize` and `limit` are set to 30 for all Open API and database fetch methods.
- **Expand Seed Fallback**: Update the seed catalogs to provide 30 items per category as a high-quality fallback.

```diff
-    final url = '$_baseUrl?category=$catId&region=$region&date_type=$periodDays&page=1&size=10&sort=gmv';
+    final url = '$_baseUrl?category=$catId&region=$region&date_type=$periodDays&page=1&size=30&sort=gmv';
...
-      pagesize: 10,
+      pagesize: 30,
...
-      {int periodDays = 7, int limit = 10}) async {
+      {int periodDays = 7, int limit = 30}) async {
```

## Verification Plan

### Manual Verification
- **Branding Check**: Verify "FastMoss" is removed from all UI elements in the "Vi mô" tab.
- **Data Volume**: Verify that the product list and creator list show up to 30 items.
- **Real Data Priority**: If a valid API token is present, verify (via logs or UI) that data is being pulled from the server rather than just showing seed data.
- **Fallback Verification**: Temporarily disable network or clear the token to ensure the expanded 30-item seed data still renders correctly.
