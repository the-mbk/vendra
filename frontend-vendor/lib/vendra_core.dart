// Barrel file — import 'package:vendra_vendor/vendra_core.dart' to get the shared
// config, models, services, and widgets. (Kept in sync by hand with the other
// Vendra Flutter apps, since each app lives in its own repo.)

export 'config/api_config.dart';
export 'config/app_theme.dart';

export 'core/models/json_utils.dart';
export 'core/models/product_model.dart';
export 'core/models/order_model.dart';
export 'core/models/user_model.dart';
export 'core/models/map_marker_data.dart';
export 'core/models/notification_model.dart';
export 'core/models/category_model.dart';
export 'core/models/dispute_model.dart';
export 'core/models/wallet_model.dart';
export 'core/models/page_meta.dart';

export 'core/services/api_service.dart';
export 'core/services/storage_service.dart';
export 'core/services/realtime_service.dart';
export 'core/services/notification_center.dart';
export 'core/services/contact_launcher.dart';

export 'core/widgets/vendra_button.dart';
export 'core/widgets/vendra_text_field.dart';
export 'core/widgets/loading_shimmer.dart';
export 'core/widgets/product_card.dart';
export 'core/widgets/map_picker_widget.dart';
export 'core/widgets/notification_bell.dart';
export 'core/widgets/product_image.dart';
export 'core/widgets/account_screens.dart';
