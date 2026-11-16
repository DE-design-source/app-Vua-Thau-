# Vua Thầu Nghiệm thu: app Android cho cộng tác viên

App Flutter dành cho **cộng tác viên (CTV)**: chụp ảnh công trình đang xây, nộp hồ sơ nghiệm thu, theo dõi duyệt và nhận tiền.
Admin và kế toán dùng **web**; app và web dùng chung một máy chủ nên chung dữ liệu.

App viết lại giao diện và chức năng của bản Expo trong `vuathau-nghiemthu/mobile` và gọi đúng các route của máy chủ
`https://nghiemthu.vuathau.com.vn`. Mọi request gửi header `X-App: 1`: GET trả dữ liệu trang dạng JSON, POST trả `{url, msgs, token}`.

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
  main.dart          khởi động: lấy /app.json, token đã lưu → Đăng nhập hoặc app
  api.dart           gọi máy chủ, lưu token (flutter_secure_storage), tải ảnh có báo %
  ui.dart            màu, icon, nút, thẻ, ô nhập dùng chung (cùng bộ màu với web)
  page.dart          tải dữ liệu trang, tự tải lại khi quay về màn
  auth.dart          đầu trang đăng nhập, Google Sign-In, 3 ô ngân hàng
  check.dart         AI kiểm ảnh (/api/kiem-anh)
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

Đổi máy chủ: `flutter build apk --dart-define=API_URL=https://may-chu-khac`.

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

App lấy `GOOGLE` (web client id) từ `/app.json`. Để nút Google hoạt động, trong Google Cloud Console (cùng project với
web client id đó) cần tạo **OAuth client loại Android** với package `vn.com.vuathau.app` và SHA-1 của khoá ký APK
(`keytool -list -v -keystore android/vuathau.jks`). Chưa làm bước này thì vẫn đăng nhập được bằng số điện thoại + mật khẩu.

## Ghi chú

- Mã gói `vn.com.vuathau.app` khác bản Expo cũ (`vn.com.vuathau.nghiemthu`), nên hai bản cài song song được.
- Bản này không tự hỏi cập nhật qua `/tai-app/phien-ban`, vì máy chủ đang trả phiên bản của app Expo.
