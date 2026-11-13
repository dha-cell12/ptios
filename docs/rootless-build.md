# Build TLinkauto cho jailbreak rootless

Ngày cập nhật: 13/11/2026 (Asia/Bangkok).

Workflow **Build** (`.github/workflows/build.yml`) có thêm runtime `rootless`, với hai artifact:

- `TLinkauto-rootless-deb-observe`
- `TLinkauto-rootless-deb-enforced`

Tổng cộng workflow tạo sáu bản package: `rootfull`, `roothide`, `rootless`, mỗi loại có `observe` và `enforced`. Các kiểm tra chung chạy một lần trước matrix; mỗi bản vẫn build, kiểm tra license/artifact và upload riêng. Workflow TrollStore riêng giữ nguyên.

## Cấu hình

| Mục | Rootless |
| --- | --- |
| Theos | Upstream `theos/theos` |
| Package scheme | `rootless` |
| Debian architecture | `iphoneos-arm64` |
| Mach-O architecture | `arm64` |
| Minimum iOS | 15.0 |
| Bootstrap/install prefix | `/var/jb` |
| App | `/var/jb/Applications/TLinkauto.app` |
| Daemon/helper | `/var/jb/usr/bin`, `/var/jb/usr/libexec` |
| Tweak | `/var/jb/Library/MobileSubstrate/DynamicLibraries` |
| Dữ liệu và license | `/var/mobile/Library/TLinkauto` |

Theo [tài liệu rootless của Theos](https://theos.dev/docs/rootless), scheme tự áp dụng install prefix, rpath và kiến trúc package. Nhánh Theos dùng `rootless.h`/libroot khi có; app Xcode độc lập dùng `/var/jb` cho bootstrap paths. Bản này nhắm jailbreak rootless chuẩn có `/var/jb`, không thay thế package RootHide dành cho bootstrap riêng.

`TLINK_ROOTLESS_RUNTIME` được truyền vào app Xcode và cả sáu subproject Theos. Các đường dẫn bootstrap như shell, sudo, helper, Activator, ảnh indicator và app lookup dùng chung `TLinkJailbreakPath`. Dữ liệu người dùng, Unix sockets và license vẫn ở thư mục `/var/mobile` hiện tại. Các marker/policy license `rootfull_*` tiếp tục chỉ cùng họ runtime jailbreak; không đổi contract hoặc giảm enforcement.

## Package và cài đặt

Hook `prepare-rootless-stage.mjs` chạy trước khi Theos áp dụng prefix lên package. Hook sửa chuỗi executable trong bốn launchd plist, đưa log vào thư mục dữ liệu ghi được và tạo maintainer scripts với shell/PATH/app/helper/sudoers paths đúng `/var/jb`. Không sửa các file layout gốc của rootfull/Roothide và không thêm prefix hai lần khi chạy lại staging.

Theos cũng prefix các file dữ liệu mẫu thành `/var/jb/var/mobile/Library/TLinkauto`. Post-install sao chép chúng vào thư mục dữ liệu dùng chung, khôi phục `config.json` đã có sau khi chép. Trường hợp chạy lại configure không có pre-install mới cũng giữ cấu hình hiện có. Script mẫu `add_datetime.sh` sử dụng bash của bootstrap rootless. Không chuyển lease, socket hoặc dữ liệu runtime sang thư mục dữ liệu mẫu dưới `/var/jb`.

Tải đúng artifact cho thiết bị rồi cài `.deb` bằng package manager của jailbreak. Ba runtime dùng chung package ID `com.tlinkauto.ioscontrol`; chỉ cài loại phù hợp với môi trường hiện tại. Bản `observe` dùng thử nghiệm; bản `enforced` giữ kiểm tra license bắt buộc.

## Build cục bộ

Trên macOS, chuẩn bị Xcode, Node.js, ldid, dpkg và Theos upstream như workflow. Build app Xcode bằng nhánh rootless của workflow trước, bao gồm `TLINK_ROOTLESS_RUNTIME=1`, `TLINK_ROOTHIDE_RUNTIME=0`, deployment target 15.0 và license mode tương ứng; chép app đã ký vào layout. Sau đó:

```sh
make clean
make package FINALPACKAGE=1 TLINK_PACKAGE_RUNTIME=rootless TLINK_LICENSE_MODE=enforced
dpkg-deb -f packages/*.deb Architecture
```

Architecture phải là `iphoneos-arm64`. Luôn `make clean` khi đổi package scheme. Trong CI, validator đọc app/binaries dưới `var/jb` của archive đã giải nén, kiểm tra marker rootless của tám Mach-O, bốn launchd executable/log paths, shell của maintainer scripts và đầy đủ gate license phase 6. Toàn bộ archive vẫn được quét secret. Các validator của rootfull và Roothide tiếp tục dùng payload root cũ.

## Xác minh

Kiểm tra staging trên Windows bao gồm bốn daemon, đường dẫn cài đặt, shared-data/config order, giữ nguồn rootfull/Roothide, chạy lại staging và từ chối input thiếu trước khi ghi. POSIX sandbox chạy maintainer scripts thật trong cây file tạm, stub các lệnh service/UI/identity; kiểm tra giữ config qua pre-install và hai lần configure, bốn service load đúng thứ tự và sudoers có prefix. Không cài package hay điều khiển service thật.

CI macOS bổ sung đánh giá Makefile cho cả sáu runtime/mode và bốn nhánh Foundation path helper: rootful, rootless app fallback, rootless SDK và RootHide SDK. Local Windows không thay thế được compile/link iOS, code signing, deb packaging hoặc kiểm tra cài trên thiết bị. Các bước này cần lần chạy GitHub Actions và thiết bị rootless thực tế.

37 kiểm tra source/build, staging rootless, POSIX install sandbox và actionlint đã pass local. Validator production cũng được chạy với sáu bộ filesystem/marker/config giả lập cho ba runtime × hai license mode, cùng ca thiếu marker rootless, launchd chưa có prefix, sai shell và secret nằm ngoài `/var/jb`. Chỉ adapter plutil/ldid được kiểm soát trong các fixture này; chữ ký và Mach-O thật vẫn phải qua validator trong CI.

### Sửa chuỗi baseline Makefile — 14/11/2026

CI dừng tại `complete C03aq pccontrol/Makefile` vì bước thêm cờ rootless chưa được khôi phục trước khi đối chiếu baseline persistence/indicator cũ. `rootless-makefile-baseline.mjs` kiểm tra hash đầy đủ của sáu Makefile hiện tại, gỡ đúng dòng mặc định/cờ rootless với số lượng đã chốt rồi đối chiếu hash đầy đủ của bản trước (`b3ee3280`). Sau đó các gate C03aq, indicator, Event và History tiếp tục chạy với hash lịch sử nguyên vẹn. Makefile production và các biến thể build không đổi.

Kiểm tra rootless bổ sung 24 trường hợp từ chối sửa ngoài phạm vi, thiếu/thừa cờ và thay license default. Toàn bộ 91 runner local đã pass trên Windows (37 source/build, 54 safety portable subsets), gồm indicator gây lỗi, Event, History và rootless artifact fixtures. Chuỗi persistence cũng từ chối sửa nguồn ngoài phạm vi; kiểm tra cú pháp JavaScript và whitespace đều pass. Compile/sign/package iOS thật vẫn cần CI.
