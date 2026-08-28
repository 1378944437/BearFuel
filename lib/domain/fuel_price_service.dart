/// 省份油价模型。价格只有在 online API 成功返回时才可用。
class ProvinceFuelPrice {
  final String province;
  final double gas92;
  final double gas95;
  final double gas98;
  final double diesel0;
  final double lastChangeAmount;
  final DateTime lastChangeDate;
  final bool isAvailable;

  const ProvinceFuelPrice({
    required this.province,
    required this.gas92,
    required this.gas95,
    required this.gas98,
    required this.diesel0,
    required this.lastChangeAmount,
    required this.lastChangeDate,
    this.isAvailable = true,
  });

  ProvinceFuelPrice.unavailable(String province)
      : province = province,
        gas92 = 0,
        gas95 = 0,
        gas98 = 0,
        diesel0 = 0,
        lastChangeAmount = 0,
        lastChangeDate = DateTime(1970),
        isAvailable = false;
}

class AdjustmentForecast {
  final DateTime nextAdjustmentDate;
  final int daysRemaining;
  final double forecastDelta;
  final bool isIncrease;
  final String direction;
  final String advice;
  final bool isAvailable;

  const AdjustmentForecast({
    required this.nextAdjustmentDate,
    required this.daysRemaining,
    required this.forecastDelta,
    required this.isIncrease,
    this.direction = '下调',
    required this.advice,
    this.isAvailable = true,
  });
}

/// 油价领域基础服务：只保留省份名称和城市映射，不内置油价示例。
class FuelPriceService {
  static const List<String> _supportedProvinces = [
    '北京',
    '上海',
    '天津',
    '重庆',
    '河北',
    '山西',
    '辽宁',
    '吉林',
    '黑龙江',
    '江苏',
    '浙江',
    '安徽',
    '福建',
    '江西',
    '山东',
    '河南',
    '湖北',
    '湖南',
    '广东',
    '海南',
    '四川',
    '贵州',
    '云南',
    '陕西',
    '甘肃',
    '青海',
    '台湾',
    '内蒙古',
    '广西',
    '西藏',
    '宁夏',
    '新疆',
  ];

  static const Map<String, String> _cityProvince = {
    '荆门': '湖北',
    '武汉': '湖北',
    '襄阳': '湖北',
    '宜昌': '湖北',
    '十堰': '湖北',
    '荆州': '湖北',
    '随州': '湖北',
    '黄冈': '湖北',
    '孝感': '湖北',
    '鄂州': '湖北',
    '咸宁': '湖北',
    '恩施': '湖北',
    '仙桃': '湖北',
    '潜江': '湖北',
    '天门': '湖北',
    '广州': '广东',
    '深圳': '广东',
    '东莞': '广东',
    '佛山': '广东',
    '珠海': '广东',
    '中山': '广东',
    '惠州': '广东',
    '江门': '广东',
    '成都': '四川',
    '绵阳': '四川',
    '杭州': '浙江',
    '宁波': '浙江',
    '南京': '江苏',
    '苏州': '江苏',
    '西安': '陕西',
    '郑州': '河南',
    '长沙': '湖南',
    '济南': '山东',
    '青岛': '山东',
    '沈阳': '辽宁',
    '长春': '吉林',
    '大连': '辽宁',
    '哈尔滨': '黑龙江',
    '福州': '福建',
    '厦门': '福建',
    '合肥': '安徽',
    '南昌': '江西',
    '南宁': '广西',
    '昆明': '云南',
    '贵阳': '贵州',
    '海口': '海南',
    '三亚': '海南',
    '太原': '山西',
    '呼和浩特': '内蒙古',
    '兰州': '甘肃',
    '银川': '宁夏',
    '西宁': '青海',
    '乌鲁木齐': '新疆',
    '拉萨': '西藏',
  };

  static List<String> getAllProvinces() => _supportedProvinces;

  static String cityToProvince(String provinceOrCity) {
    final normalized = provinceOrCity.trim().replaceFirst(
          RegExp(r'(自治区|自治州|地区|省|市)$'),
          '',
        );
    if (_supportedProvinces.contains(normalized)) return normalized;
    return _cityProvince[normalized] ?? normalized;
  }

  static ProvinceFuelPrice getProvincePrice(String provinceOrCity) {
    final province = cityToProvince(provinceOrCity);
    return ProvinceFuelPrice.unavailable(province);
  }

  static AdjustmentForecast getAdjustmentForecast() {
    return AdjustmentForecast(
      nextAdjustmentDate: DateTime(1970),
      daysRemaining: 0,
      forecastDelta: 0,
      isIncrease: false,
      advice: '暂无在线调价预测数据',
      isAvailable: false,
    );
  }
}
