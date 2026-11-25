# Vua Thầu Nghiệm thu: app Android cho cộng tác viên

App Flutter dành cho **cộng tác viên (CTV)**: chụp ảnh công trình đang xây, nộp hồ sơ nghiệm thu, theo dõi duyệt và nhận tiền.
Admin và kế toán dùng **web**; app và web dùng chung một máy chủ nên chung dữ liệu.

App viết lại giao diện và chức năng của bản Expo trong `vuathau-nghiemthu/mobile`. Máy chủ là **backend Go** trong repo
`DE-design-source/VuaThau` (thư mục `backend`), dùng chung với web quản lý của admin và kế toán. App gọi API REST
`https://map.vuathau.com.vn/api/v1`:

- Mọi response là envelope `{"success": true, "data": ...}` hoặc `{"success": false, "error": "..."}`; app trả `data`, báo `error`.
- Đăng nhập (`POST /auth/login`, `/auth/register`, `/auth/google`) trả JWT; app lưu bằng flutter_secure_storage và gửi
  `Authorization: Bearer <token>`. Gặp 401 (hết phiên, đổi mật khẩu, bị khoá): app xoá token, về màn Đăng nhập.
- POST/PUT gửi JSON; tải ảnh lên là multipart (`files` + `meta`).
- Hợp đồng API đầy đủ: `backend/docs/nghiemthu-api.md` trong repo VuaThau.

## Chức năng

| Màn | Nội dung |
|---|---|
| Đăng nhập / Đăng ký | Số điện thoại + mật khẩu, hoặc Google. Đăng ký kèm tài khoản ngân hàng nhận tiền. Tài khoản admin/kế toán không vào được app. |
| Hồ sơ | Tiền đã nhận, chờ thanh toán, chờ duyệt; tiến độ gom đủ hồ sơ để được trả; lọc theo trạng thái; danh sách hồ sơ. |
| Nộp ảnh | Camera Vua Thầu (in giờ, thứ, ngày, địa chỉ, toạ độ GPS lên ảnh kiểu Timemark) hoặc chọn ảnh có sẵn. AI kiểm từng ảnh ngay khi chụp/chọn. |
| Chi tiết hồ sơ | Phản hồi AI, lưới ảnh (xem lớn, xoá), tiền dự kiến, thông tin công trình (AI điền sẵn), tiến trình, lịch sử, Lưu nháp / Gửi duyệt. |
| Thu nhập | Lần thanh toán tới, tài khoản nhận tiền, thưởng/trừ, lịch sử nhận tiền → phiếu chi (mã giao dịch, ảnh biên lai). |
| Tài khoản | Sửa ngân hàng, đổi mật khẩu, quy tắc nghiệm thu, xoá tài khoản, đăng xuất. |

## Cấu trúc

```
lib/
  main.dart          khởi động: lấy GET /config, token đã lưu → Đăng nhập hoặc app
  api.dart           gọi /api/v1 (envelope, JWT), lưu token (flutter_secure_storage), tải ảnh có báo %
  ui.dart            màu, icon, nút, thẻ, ô nhập dùng chung (cùng bộ màu với web)
  page.dart          tải dữ liệu trang, tự tải lại khi quay về màn
  auth.dart          đầu trang đăng nhập, Google Sign-In, 3 ô ngân hàng
  check.dart         AI kiểm ảnh (POST /photos/check)
  picker.dart        chọn ảnh có sẵn + tải lên
  stamp.dart         vẽ dải chữ Timemark lên khung ngắm và ảnh
  screens/           các màn hình
```

## Build

Cần Flutter 3.50+ và Android SDK.

```bash
flutter pub get
flutter test
flutter build apk --release                 # build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release --split-per-abi # APK nhỏ hơn cho từng loại máy
```

### File .env

Cấu hình đặt ở gốc repo, **không có trong git** (xin file mẫu từ admin):
`.env` cho máy dev (`flutter run`), `.env.production` chỉ khi build bản phát hành trỏ máy chủ khác.

Hiện chỉ có `API_URL`: gốc máy chủ (app tự thêm `/api/v1`); để trống hoặc không truyền file = máy chủ thật
`https://map.vuathau.com.vn`.

```bash
echo API_URL=http://10.0.2.2:8080 > .env   # máy ảo Android gọi backend Go trên máy tính
flutter run --dart-define-from-file=.env
flutter build apk --release      # bản phát hành: không truyền .env của máy dev
flutter build apk --release --dart-define-from-file=.env.production   # khi cần trỏ máy chủ khác
```

Vẫn dùng được `--dart-define=API_URL=...` như trước.

Bản debug cho phép gọi `http://` (`android/app/src/debug/AndroidManifest.xml`); bản release chỉ gọi `https://`.

### Ký bản phát hành

Chưa có khoá thì APK được ký bằng khoá debug (cài thử được, không lên CH Play được). Tạo khoá:

```bash
keytool -genkey -v -keystore android/vuathau.jks -keyalg RSA -keysize 2048 -validity 10000 -alias vuathau
```

rồi tạo `android/key.properties` (đã nằm trong .gitignore, **không** đưa lên git):

```
storeFile=../vuathau.jks
storePassword=...
keyAlias=vuathau
keyPassword=...
```

### Đăng nhập bằng Google

App lấy `google_client_id` (web client id) từ `GET /api/v1/config`. Để nút Google hoạt động, trong Google Cloud Console (cùng project với
web client id đó) cần tạo **OAuth client loại Android** với package `vn.com.vuathau.app` và SHA-1 của khoá ký APK
(`keytool -list -v -keystore android/vuathau.jks`). Chưa làm bước này thì vẫn đăng nhập được bằng số điện thoại + mật khẩu.

## Ghi chú

- Mã gói `vn.com.vuathau.app` khác bản Expo cũ (`vn.com.vuathau.nghiemthu`), nên hai bản cài song song được.
- Bản này không tự hỏi cập nhật qua `/tai-app/phien-ban`, vì máy chủ đang trả phiên bản của app Expo.
