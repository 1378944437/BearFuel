/// 全国城市静态数据模型
class ChinaCity {
  final String name; // 城市名，如 "温州"
  final String province; // 所属省级，如 "浙江"
  final String pinyin; // 全拼（小写，ü 以 v 表示），如 "wenzhou"
  final String initials; // 拼音首字母，如 "wz"

  const ChinaCity(this.name, this.province, this.pinyin, this.initials);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChinaCity && other.name == name && other.province == province);

  @override
  int get hashCode => Object.hash(name, province);

  @override
  String toString() => '$name（$province）';
}

/// 全国省级行政区 + 地级行政区静态数据集，
/// 支撑城市选择器的全量搜索（中文名 / 省份 / 全拼 / 拼音首字母）。
class ChinaCities {
  ChinaCities._();

  /// 热门城市（默认展示在九宫格中）
  static const List<String> hotCities = [
    '北京',
    '上海',
    '广州',
    '深圳',
    '天津',
    '杭州',
    '东莞',
    '宁波',
    '西安',
    '成都',
    '重庆',
    '南京',
    '苏州',
    '武汉',
    '厦门',
    '福州',
    '昆明',
    '沈阳',
    '长春',
    '大连',
    '荆门',
    '宜昌',
    '襄阳',
    '荆州',
    '长沙',
    '郑州',
    '济南',
    '青岛',
    '合肥',
    '南昌',
    '南宁',
    '贵阳',
    '海口',
    '三亚',
    '哈尔滨',
    '太原',
    '兰州',
    '乌鲁木齐',
    '呼和浩特',
    '银川',
    '西宁',
    '拉萨',
  ];

  /// 34 个省级行政区简称
  static const List<String> provinces = [
    '北京',
    '天津',
    '河北',
    '山西',
    '内蒙古',
    '辽宁',
    '吉林',
    '黑龙江',
    '上海',
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
    '广西',
    '海南',
    '重庆',
    '四川',
    '贵州',
    '云南',
    '西藏',
    '陕西',
    '甘肃',
    '青海',
    '宁夏',
    '新疆',
    '香港',
    '澳门',
    '台湾',
  ];

  /// 数据格式: 名称|省份|全拼|首字母
  static const List<String> _raw = [
    // 直辖市
    '北京|北京|beijing|bj',
    '天津|天津|tianjin|tj',
    '上海|上海|shanghai|sh',
    '重庆|重庆|chongqing|cq',
    // 河北
    '石家庄|河北|shijiazhuang|sjz',
    '唐山|河北|tangshan|ts',
    '秦皇岛|河北|qinhuangdao|qhd',
    '邯郸|河北|handan|hd',
    '邢台|河北|xingtai|xt',
    '保定|河北|baoding|bd',
    '张家口|河北|zhangjiakou|zjk',
    '承德|河北|chengde|cd',
    '沧州|河北|cangzhou|cz',
    '廊坊|河北|langfang|lf',
    '衡水|河北|hengshui|hs',
    // 山西
    '太原|山西|taiyuan|ty',
    '大同|山西|datong|dt',
    '阳泉|山西|yangquan|yq',
    '长治|山西|changzhi|cz',
    '晋城|山西|jincheng|jc',
    '朔州|山西|shuozhou|sz',
    '晋中|山西|jinzhong|jz',
    '运城|山西|yuncheng|yc',
    '忻州|山西|xinzhou|xz',
    '临汾|山西|linfen|lf',
    '吕梁|山西|lvliang|ll',
    // 内蒙古
    '呼和浩特|内蒙古|huhehaote|hhht',
    '包头|内蒙古|baotou|bt',
    '乌海|内蒙古|wuhai|wh',
    '赤峰|内蒙古|chifeng|cf',
    '通辽|内蒙古|tongliao|tl',
    '鄂尔多斯|内蒙古|eerduosi|eeds',
    '呼伦贝尔|内蒙古|hulunbeier|hlbe',
    '巴彦淖尔|内蒙古|bayannaoer|byne',
    '乌兰察布|内蒙古|wulanchabu|wlcb',
    '兴安盟|内蒙古|xinganmeng|xam',
    '锡林郭勒盟|内蒙古|xilinguolemeng|xlglm',
    '阿拉善盟|内蒙古|alashanmeng|alsm',
    // 辽宁
    '沈阳|辽宁|shenyang|sy',
    '大连|辽宁|dalian|dl',
    '鞍山|辽宁|anshan|as',
    '抚顺|辽宁|fushun|fs',
    '本溪|辽宁|benxi|bx',
    '丹东|辽宁|dandong|dd',
    '锦州|辽宁|jinzhou|jz',
    '营口|辽宁|yingkou|yk',
    '阜新|辽宁|fuxin|fx',
    '辽阳|辽宁|liaoyang|ly',
    '盘锦|辽宁|panjin|pj',
    '铁岭|辽宁|tieling|tl',
    '朝阳|辽宁|chaoyang|cy',
    '葫芦岛|辽宁|huludao|hld',
    // 吉林
    '长春|吉林|changchun|cc',
    '吉林|吉林|jilin|jl',
    '四平|吉林|siping|sp',
    '辽源|吉林|liaoyuan|ly',
    '通化|吉林|tonghua|th',
    '白山|吉林|baishan|bs',
    '松原|吉林|songyuan|sy',
    '白城|吉林|baicheng|bc',
    '延边|吉林|yanbian|yb',
    // 黑龙江
    '哈尔滨|黑龙江|haerbin|heb',
    '齐齐哈尔|黑龙江|qiqihaer|qqhe',
    '鸡西|黑龙江|jixi|jx',
    '鹤岗|黑龙江|hegang|hg',
    '双鸭山|黑龙江|shuangyashan|sys',
    '大庆|黑龙江|daqing|dq',
    '伊春|黑龙江|yichun|yc',
    '佳木斯|黑龙江|jiamusi|jms',
    '七台河|黑龙江|qitaihe|qth',
    '牡丹江|黑龙江|mudanjiang|mdj',
    '黑河|黑龙江|heihe|hh',
    '绥化|黑龙江|suihua|sh',
    '大兴安岭|黑龙江|daxinganling|dxal',
    // 江苏
    '南京|江苏|nanjing|nj',
    '无锡|江苏|wuxi|wx',
    '徐州|江苏|xuzhou|xz',
    '常州|江苏|changzhou|cz',
    '苏州|江苏|suzhou|sz',
    '南通|江苏|nantong|nt',
    '连云港|江苏|lianyungang|lyg',
    '淮安|江苏|huaian|ha',
    '盐城|江苏|yancheng|yc',
    '扬州|江苏|yangzhou|yz',
    '镇江|江苏|zhenjiang|zj',
    '泰州|江苏|taizhou|tz',
    '宿迁|江苏|suqian|sq',
    // 浙江
    '杭州|浙江|hangzhou|hz',
    '宁波|浙江|ningbo|nb',
    '温州|浙江|wenzhou|wz',
    '嘉兴|浙江|jiaxing|jx',
    '湖州|浙江|huzhou|hzh',
    '绍兴|浙江|shaoxing|sx',
    '金华|浙江|jinhua|jh',
    '衢州|浙江|quzhou|qz',
    '舟山|浙江|zhoushan|zs',
    '台州|浙江|taizhou|tzh',
    '丽水|浙江|lishui|ls',
    // 安徽
    '合肥|安徽|hefei|hf',
    '芜湖|安徽|wuhu|wh',
    '蚌埠|安徽|bengbu|bb',
    '淮南|安徽|huainan|hn',
    '马鞍山|安徽|maanshan|mas',
    '淮北|安徽|huaibei|hb',
    '铜陵|安徽|tongling|tl',
    '安庆|安徽|anqing|aq',
    '黄山|安徽|huangshan|hs',
    '滁州|安徽|chuzhou|chz',
    '阜阳|安徽|fuyang|fy',
    '宿州|安徽|suzhou|szh',
    '六安|安徽|liuan|la',
    '亳州|安徽|bozhou|bz',
    '池州|安徽|chizhou|chzh',
    '宣城|安徽|xuancheng|xc',
    // 福建
    '福州|福建|fuzhou|fz',
    '厦门|福建|xiamen|xm',
    '莆田|福建|putian|pt',
    '三明|福建|sanming|sm',
    '泉州|福建|quanzhou|qz',
    '漳州|福建|zhangzhou|zz',
    '南平|福建|nanping|np',
    '龙岩|福建|longyan|ly',
    '宁德|福建|ningde|nd',
    // 江西
    '南昌|江西|nanchang|nc',
    '景德镇|江西|jingdezhen|jdz',
    '萍乡|江西|pingxiang|px',
    '九江|江西|jiujiang|jj',
    '新余|江西|xinyu|xy',
    '鹰潭|江西|yingtan|yt',
    '赣州|江西|ganzhou|gz',
    '吉安|江西|jian|ja',
    '宜春|江西|yichun|ych',
    '抚州|江西|fuzhou|fzh',
    '上饶|江西|shangrao|sr',
    // 山东
    '济南|山东|jinan|jn',
    '青岛|山东|qingdao|qd',
    '淄博|山东|zibo|zb',
    '枣庄|山东|zaozhuang|zz',
    '东营|山东|dongying|dy',
    '烟台|山东|yantai|yt',
    '潍坊|山东|weifang|wf',
    '济宁|山东|jining|jng',
    '泰安|山东|taian|ta',
    '威海|山东|weihai|wh',
    '日照|山东|rizhao|rz',
    '临沂|山东|linyi|ly',
    '德州|山东|dezhou|dz',
    '聊城|山东|liaocheng|lc',
    '滨州|山东|binzhou|bz',
    '菏泽|山东|heze|hz',
    // 河南
    '郑州|河南|zhengzhou|zz',
    '开封|河南|kaifeng|kf',
    '洛阳|河南|luoyang|ly',
    '平顶山|河南|pingdingshan|pds',
    '安阳|河南|anyang|ay',
    '鹤壁|河南|hebi|hb',
    '新乡|河南|xinxiang|xx',
    '焦作|河南|jiaozuo|jz',
    '濮阳|河南|puyang|py',
    '许昌|河南|xuchang|xc',
    '漯河|河南|luohe|lh',
    '三门峡|河南|sanmenxia|smx',
    '南阳|河南|nanyang|ny',
    '商丘|河南|shangqiu|sq',
    '信阳|河南|xinyang|xy',
    '周口|河南|zhoukou|zk',
    '驻马店|河南|zhumadian|zmd',
    '济源|河南|jiyuan|jy',
    // 湖北
    '武汉|湖北|wuhan|wh',
    '黄石|湖北|huangshi|hs',
    '十堰|湖北|shiyan|sy',
    '宜昌|湖北|yichang|yc',
    '襄阳|湖北|xiangyang|xy',
    '鄂州|湖北|ezhou|ez',
    '荆门|湖北|jingmen|jm',
    '孝感|湖北|xiaogan|xg',
    '荆州|湖北|jingzhou|jzh',
    '黄冈|湖北|huanggang|hg',
    '咸宁|湖北|xianning|xn',
    '随州|湖北|suizhou|suiz',
    '恩施|湖北|ensi|es',
    '仙桃|湖北|xiantao|xt',
    '潜江|湖北|qianjiang|qj',
    '天门|湖北|tianmen|tm',
    '神农架|湖北|shennongjia|snj',
    // 湖南
    '长沙|湖南|changsha|cs',
    '株洲|湖南|zhuzhou|zhu',
    '湘潭|湖南|xiangtan|xt',
    '衡阳|湖南|hengyang|hy',
    '邵阳|湖南|shaoyang|sy',
    '岳阳|湖南|yueyang|yy',
    '常德|湖南|changde|cd',
    '张家界|湖南|zhangjiajie|zjj',
    '益阳|湖南|yiyang|yy',
    '郴州|湖南|chenzhou|chzh',
    '永州|湖南|yongzhou|yz',
    '怀化|湖南|huaihua|hh',
    '娄底|湖南|loudi|ld',
    '湘西|湖南|xiangxi|xx',
    // 广东
    '广州|广东|guangzhou|gz',
    '韶关|广东|shaoguan|sg',
    '深圳|广东|shenzhen|sz',
    '珠海|广东|zhuhai|zh',
    '汕头|广东|shantou|st',
    '佛山|广东|foshan|fs',
    '江门|广东|jiangmen|jm',
    '湛江|广东|zhanjiang|zj',
    '茂名|广东|maoming|mm',
    '肇庆|广东|zhaoqing|zq',
    '惠州|广东|huizhou|hzh',
    '梅州|广东|meizhou|mz',
    '汕尾|广东|shanwei|sw',
    '河源|广东|heyuan|hy',
    '阳江|广东|yangjiang|yj',
    '清远|广东|qingyuan|qy',
    '东莞|广东|dongguan|dg',
    '中山|广东|zhongshan|zs',
    '潮州|广东|chaozhou|cz',
    '揭阳|广东|jieyang|jy',
    '云浮|广东|yunfu|yf',
    // 广西
    '南宁|广西|nanning|nn',
    '柳州|广西|liuzhou|lz',
    '桂林|广西|guilin|gl',
    '梧州|广西|wuzhou|wzh',
    '北海|广西|beihai|bh',
    '防城港|广西|fangchenggang|fcg',
    '钦州|广西|qinzhou|qzh',
    '贵港|广西|guigang|gg',
    '玉林|广西|yulin|yl',
    '百色|广西|baise|bs',
    '贺州|广西|hezhou|hz',
    '河池|广西|hechi|hc',
    '来宾|广西|laibin|lb',
    '崇左|广西|chongzuo|cz',
    // 海南
    '海口|海南|haikou|hk',
    '三亚|海南|sanya|sy',
    '三沙|海南|sansha|ss',
    '儋州|海南|danzhou|dz',
    // 四川
    '成都|四川|chengdu|cd',
    '自贡|四川|zigong|zg',
    '攀枝花|四川|panzhihua|pzh',
    '泸州|四川|luzhou|lzh',
    '德阳|四川|deyang|dy',
    '绵阳|四川|mianyang|my',
    '广元|四川|guangyuan|gy',
    '遂宁|四川|suining|sn',
    '内江|四川|neijiang|nj',
    '乐山|四川|leshan|ls',
    '南充|四川|nanchong|nch',
    '眉山|四川|meishan|ms',
    '宜宾|四川|yibin|yb',
    '广安|四川|guangan|ga',
    '达州|四川|dazhou|dzh',
    '雅安|四川|yaan|ya',
    '巴中|四川|bazhong|bzh',
    '资阳|四川|ziyang|zy',
    '阿坝|四川|aba|ab',
    '甘孜|四川|ganzi|gz',
    '凉山|四川|liangshan|ls',
    // 贵州
    '贵阳|贵州|guiyang|gy',
    '六盘水|贵州|liupanshui|lps',
    '遵义|贵州|zunyi|zy',
    '安顺|贵州|anshun|as',
    '毕节|贵州|bijie|bj',
    '铜仁|贵州|tongren|tr',
    '黔西南|贵州|qianxinan|qxn',
    '黔东南|贵州|qiandongnan|qdn',
    '黔南|贵州|qiannan|qn',
    // 云南
    '昆明|云南|kunming|km',
    '曲靖|云南|qujing|qj',
    '玉溪|云南|yuxi|yx',
    '保山|云南|baoshan|bs',
    '昭通|云南|zhaotong|zt',
    '丽江|云南|lijiang|lj',
    '普洱|云南|puer|pe',
    '临沧|云南|lincang|lc',
    '楚雄|云南|chuxiong|cx',
    '红河|云南|honghe|hh',
    '文山|云南|wenshan|ws',
    '西双版纳|云南|xishuangbanna|xsbn',
    '大理|云南|dali|dl',
    '德宏|云南|dehong|dh',
    '怒江|云南|nujiang|nj',
    '迪庆|云南|diqing|dq',
    // 西藏
    '拉萨|西藏|lasa|ls',
    '日喀则|西藏|rikaze|rkz',
    '昌都|西藏|changdu|cd',
    '林芝|西藏|linzhi|lz',
    '山南|西藏|shannan|sn',
    '那曲|西藏|naqu|nq',
    '阿里|西藏|ali|al',
    // 陕西
    '西安|陕西|xian|xa',
    '铜川|陕西|tongchuan|tc',
    '宝鸡|陕西|baoji|bj',
    '咸阳|陕西|xianyang|xy',
    '渭南|陕西|weinan|wn',
    '延安|陕西|yanan|ya',
    '汉中|陕西|hanzhong|hz',
    '榆林|陕西|yulin|yul',
    '安康|陕西|ankang|ak',
    '商洛|陕西|shangluo|sl',
    // 甘肃
    '兰州|甘肃|lanzhou|lz',
    '嘉峪关|甘肃|jiayuguan|jyg',
    '金昌|甘肃|jinchang|jc',
    '白银|甘肃|baiyin|by',
    '天水|甘肃|tianshui|ts',
    '武威|甘肃|wuwei|ww',
    '张掖|甘肃|zhangye|zy',
    '平凉|甘肃|pingliang|pl',
    '酒泉|甘肃|jiuquan|jq',
    '庆阳|甘肃|qingyang|qy',
    '定西|甘肃|dingxi|dx',
    '陇南|甘肃|longnan|ln',
    '临夏|甘肃|linxia|lx',
    '甘南|甘肃|gannan|gn',
    // 青海
    '西宁|青海|xining|xn',
    '海东|青海|haidong|hd',
    '海北|青海|haibei|hb',
    '黄南|青海|huangnan|hn',
    '海南州|青海|hainanzhou|hnz',
    '果洛|青海|guoluo|gl',
    '玉树|青海|yushu|ys',
    '海西|青海|haixi|hx',
    // 宁夏
    '银川|宁夏|yinchuan|yc',
    '石嘴山|宁夏|shizuishan|szs',
    '吴忠|宁夏|wuzhong|wzh',
    '固原|宁夏|guyuan|gy',
    '中卫|宁夏|zhongwei|zw',
    // 新疆
    '乌鲁木齐|新疆|wulumuqi|wlmq',
    '克拉玛依|新疆|kelamayi|klmy',
    '吐鲁番|新疆|tulufan|tlf',
    '哈密|新疆|hami|hm',
    '昌吉|新疆|changji|cj',
    '博尔塔拉|新疆|boertala|betl',
    '巴音郭楞|新疆|bayinguoleng|bygl',
    '阿克苏|新疆|akesu|aks',
    '克孜勒苏|新疆|kezilesu|kzlz',
    '喀什|新疆|kashi|ks',
    '和田|新疆|hetian|ht',
    '伊犁|新疆|yili|yl',
    '塔城|新疆|tacheng|tc',
    '阿勒泰|新疆|aletai|alt',
    '石河子|新疆|shihezi|shz',
    // 港澳台
    '香港|香港|xianggang|xg',
    '澳门|澳门|aomen|am',
    '台北|台湾|taibei|tb',
    '高雄|台湾|gaoxiong|gx',
    '台中|台湾|taizhong|tzhg',
    '台南|台湾|tainan|tn',
  ];

  static List<ChinaCity>? _cachedAll;

  /// 全部地级及以上城市（首次访问时解析，之后返回缓存）
  static List<ChinaCity> get all {
    final cached = _cachedAll;
    if (cached != null) return cached;
    final list = <ChinaCity>[];
    for (final row in _raw) {
      final parts = row.split('|');
      if (parts.length == 4) {
        list.add(ChinaCity(parts[0], parts[1], parts[2], parts[3]));
      }
    }
    return _cachedAll = list;
  }

  /// 按中文名 / 省份 / 全拼 / 拼音首字母搜索城市，
  /// 结果按匹配相关度排序（名称命中优先于拼音命中）。
  static List<ChinaCity> search(String rawQuery, {int limit = 80}) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];

    // [相关度, 原始顺序, 城市]
    final scored = <(int, int, ChinaCity)>[];
    for (var i = 0; i < all.length; i++) {
      final city = all[i];
      int? score;
      if (city.name == q) {
        score = 0;
      } else if (city.name.startsWith(q)) {
        score = 1;
      } else if (city.pinyin == q) {
        score = 2;
      } else if (city.pinyin.startsWith(q)) {
        score = 3;
      } else if (city.initials == q) {
        score = 4;
      } else if (city.initials.startsWith(q)) {
        score = 5;
      } else if (city.name.contains(q)) {
        score = 6;
      } else if (city.province.contains(q)) {
        score = 7;
      } else if (city.pinyin.contains(q)) {
        score = 8;
      }
      if (score != null) {
        scored.add((score, i, city));
      }
    }

    scored.sort((a, b) {
      final byScore = a.$1.compareTo(b.$1);
      return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
    });
    return scored.take(limit).map((e) => e.$3).toList();
  }
}
