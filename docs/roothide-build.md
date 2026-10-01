# Build và cài đặt TLinkauto cho Roothide

Repository tạo hai loại gói độc lập từ cùng mã nguồn:

- `rootfull`: gói hiện tại, kiến trúc Debian `iphoneos-arm`.
- `roothide`: gói cho RootHide Bootstrap, kiến trúc Debian `iphoneos-arm64e`, iOS 15 trở lên.

Hai gói dùng cùng package id `com.tlinkauto.ioscontrol`, vì vậy chỉ cài một loại tại một thời điểm. Không cài đè gói Roothide lên một jailbreak rootful đang hoạt động hoặc ngược lại.

## Build bằng GitHub Actions

Workflow `.github/workflows/build.yml` tự tạo bốn artifact:

- `TLinkauto-rootfull-deb-observe`
- `TLinkauto-rootfull-deb-enforced`
- `TLinkauto-roothide-deb-observe`
- `TLinkauto-roothide-deb-enforced`

Các biến public-key license vẫn dùng chung với bản rootful. Bản `enforced` chặn khi license không hợp lệ; bản `observe` chỉ ghi nhận để thử nghiệm.

1. Push branch lên GitHub hoặc chạy workflow **Build** thủ công theo cơ chế hiện có của repository.
2. Chờ đủ bốn job hoàn tất.
3. Tải artifact có tên `TLinkauto-roothide-deb-enforced` để phát hành, hoặc `observe` để test.
4. Kiểm tra file JSON manifest đi kèm có `package_runtime` bằng `roothide`.

CI sẽ từ chối artifact Roothide nếu:

- Debian architecture không phải `iphoneos-arm64e`.
- Mach-O thiếu entitlement bắt buộc của Roothide.
- License public key trong app khác cấu hình CI.
- Một trong các kiểm tra license phase 0–6 thất bại.

## Build cục bộ trên macOS

Yêu cầu Xcode, Homebrew, Node.js và fork Theos của RootHide:

```sh
export THEOS="$HOME/theos-roothide"
git clone --recursive https://github.com/roothide/theos.git "$THEOS"
"$THEOS/bin/update-theos"
brew install ldid dpkg
```

App Xcode phải được build và chép vào `layout/Applications/TLinkauto.app` giống workflow CI. Sau đó build package:

```sh
make clean
make package FINALPACKAGE=1 \
  TLINK_PACKAGE_RUNTIME=roothide \
  TLINK_LICENSE_MODE=enforced
```

File `.deb` được tạo trong `packages/`. Xác nhận architecture trước khi cài:

```sh
dpkg-deb -f packages/*.deb Architecture
```

Kết quả bắt buộc là `iphoneos-arm64e`.

## Cài trên thiết bị

1. Thiết bị phải đang chạy RootHide Bootstrap và đã bật jailbreak environment.
2. Gỡ bản TLinkauto rootful cũ nếu trước đó đã chuyển môi trường jailbreak.
3. Chép file `.deb` Roothide vào thiết bị rồi cài bằng Sileo/Zebra hoặc package manager trong bootstrap.
4. Respring nếu package manager chưa tự thực hiện.
5. Mở TLinkauto, kích hoạt license và kiểm tra các daemon `tlinkautod`, `tlinkauto-licensed`, `tlinkauto-jsd`.

Dữ liệu người dùng và lease license vẫn nằm ở `/var/mobile/Library/TLinkauto`. Trong maintainer script của bootstrap, mã cài đặt tự dùng `/rootfs/var/mobile/Library/TLinkauto` để trỏ đúng dữ liệu thật, tránh tạo một bản dữ liệu riêng bên trong jbroot.
Payload cấu hình và script mẫu cũng được sao chép từ jbroot sang thư mục dữ liệu thật ở lần cài/upgrade; file `config.json` hiện có được backup và khôi phục sau khi sao chép.

## Thiết kế tương thích Roothide

`shared/TLinkJailbreakPath.h` chuyển các đường dẫn thuộc bootstrap qua `jbroot()` tại runtime. Nếu app Xcode chưa liên kết trực tiếp `libroothide`, helper dùng symlink `.jbroot` đặt cạnh Mach-O. Đường dẫn iOS thật như `/var/mobile`, MobileGestalt và system frameworks không bị chuyển đổi.

Không hard-code đường dẫn jbroot ngẫu nhiên của một thiết bị vào source, plist hoặc database.
