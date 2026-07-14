import 'package:flutter/material.dart';

class MarketAsset {
  final String id;
  final String name;
  final String price;
  final String change;
  final bool up;
  final double gaugeValue;
  final List<double> history;
  final List<double> weekData;
  final String gaugeTitle;
  final String chartTitle;
  final Color color;
  final String badgeText;
  final Color badgeBg;
  final Color badgeTextColor;

  MarketAsset({
    required this.id,
    required this.name,
    required this.price,
    required this.change,
    required this.up,
    required this.gaugeValue,
    required this.history,
    required this.weekData,
    required this.gaugeTitle,
    required this.chartTitle,
    required this.color,
    required this.badgeText,
    required this.badgeBg,
    required this.badgeTextColor,
  });
}

// Mock Data provider
class MarketData {
  static final List<MarketAsset> assets = [
    MarketAsset(
      id: 'gold',
      name: 'Vàng SJC',
      price: '92.5 tr',
      change: '+1.8%',
      up: true,
      gaugeValue: 42,
      history: [85.2, 86.1, 86.8, 87.5, 88.2, 87.9, 88.5, 89.2, 90.1, 89.8, 90.5, 91.2, 91.8, 92.5],
      weekData: [90.1, 90.8, 91.2, 90.9, 91.5, 92.0, 92.5],
      gaugeTitle: 'Nhiệt độ FOMO — Vàng',
      chartTitle: 'Biểu đồ giá Vàng SJC',
      color: const Color(0xFFFFD54F),
      badgeText: '⚡ ẤM',
      badgeBg: const Color(0xFFFFCA28).withOpacity(0.12),
      badgeTextColor: const Color(0xFFFFCA28),
    ),
    MarketAsset(
      id: 'bds',
      name: 'BDS Hà Nội',
      price: '68.2 tr/m²',
      change: '-0.3%',
      up: false,
      gaugeValue: 28,
      history: [65.5, 66.2, 66.8, 67.1, 67.5, 67.8, 68.0, 68.3, 68.5, 68.2, 68.0, 67.8, 68.1, 68.2],
      weekData: [68.5, 68.3, 68.1, 68.0, 67.9, 68.0, 68.2],
      gaugeTitle: 'Nhiệt độ FOMO — BDS',
      chartTitle: 'Biểu đồ giá BDS Hà Nội',
      color: const Color(0xFF26C6DA),
      badgeText: '✅ AN TOÀN',
      badgeBg: const Color(0xFF00E676).withOpacity(0.12),
      badgeTextColor: const Color(0xFF00E676),
    ),
    MarketAsset(
      id: 'stock',
      name: 'VN-Index',
      price: '1,285 điểm',
      change: '+0.6%',
      up: true,
      gaugeValue: 65,
      history: [1220, 1235, 1248, 1260, 1255, 1268, 1275, 1262, 1270, 1278, 1285, 1280, 1282, 1285],
      weekData: [1262, 1270, 1275, 1268, 1280, 1278, 1285],
      gaugeTitle: 'Nhiệt độ FOMO — Chứng khoán',
      chartTitle: 'Biểu đồ VN-Index',
      color: const Color(0xFF7C4DFF),
      badgeText: '🔥 ĐỘT BIẾN',
      badgeBg: const Color(0xFFFF9100).withOpacity(0.12),
      badgeTextColor: const Color(0xFFFF9100),
    ),
    MarketAsset(
      id: 'rate',
      name: 'Lãi suất gửi',
      price: '5.2%',
      change: '+0.1%',
      up: true,
      gaugeValue: 35,
      history: [4.8, 4.9, 5.0, 5.1, 5.0, 5.2, 5.3, 5.2, 5.1, 5.0, 5.2, 5.2, 5.2, 5.2],
      weekData: [5.0, 5.1, 5.2, 5.2, 5.2, 5.2, 5.2],
      gaugeTitle: 'Nhiệt độ Lãi suất',
      chartTitle: 'Biểu đồ Lãi suất (12 tháng)',
      color: const Color(0xFF00B0FF),
      badgeText: '✅ ỔN ĐỊNH',
      badgeBg: const Color(0xFF00E676).withOpacity(0.12),
      badgeTextColor: const Color(0xFF00E676),
    ),
  ];
}
