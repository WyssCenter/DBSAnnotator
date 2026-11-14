/// The Wyss Center palette as ARGB integers.
///
/// Here rather than in `lib/ui/theme.dart` because the report builders need it
/// too, and `lib/report/` must not import `lib/ui/`: the dependency already
/// runs the other way, with seven UI files importing `report_data.dart`. The
/// alternative, re-typing the hex values in the report layer, is what let the
/// on-screen bands and the printed table disagree about which block won.
library;

// Primary.
const int kGreenLighter = 0xFF95F9D8;
const int kGreen = 0xFF0DE69F;
const int kPink = 0xFFE541F6;
const int kBlack = 0xFF000000;
const int kGreyLighter = 0xFFF8F8F8;

// Secondary.
const int kYellowLime = 0xFFDFFE80;
const int kPinkLight = 0xFFEF8AF9;
const int kBlueLight = 0xFF77B3F8;
const int kRedLight = 0xFFFFBB99;
const int kGreyDark = 0xFF6F6F6F;
const int kGreyMid = 0xFF949494;
const int kGrey = 0xFFD8D8D8;
const int kGreyLight = 0xFFE6E6E6;

/// Rank 1 and rank 2 in shaded rows and chart bands: muted greens as light as
/// the brand pair, with hatch density also carrying the order in monochrome.
const int kBestFill = 0xFFA8D2BA;
const int kSecondFill = 0xFFD6EADE;

/// Report chrome: rules, footers, meta lines and table header fills.
///
/// [kInkMuted] is 5.02:1 on white, so a footer set in it still passes AA.
const int kInkMuted = kGreyDark;
const int kRuleColor = kGreyMid;
const int kHeaderFill = kGreyLight;
const int kPanelFill = kGreyLighter;
