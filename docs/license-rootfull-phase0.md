# License Rootfull - Phase 0

> Phase 0 da hoan thanh va duoc tiep noi boi
> `docs/license-rootfull-phase1.md`. Noi dung duoi day la baseline lich su.

## Muc tieu

Phase 0 dong bang contract va chuoi build truoc khi dua shared verifier vao
runtime rootfull. Phase nay **khong gate task** va khong tu nhan goi
`enforced` da co bao ve runtime.

Hai bien the build:

- `observe`: marker `rootfull_observe_compile_time_v1`.
- `enforced`: marker `rootfull_enforced_compile_time_v1`.

Ca hai van cho phep truy cap nhu ban rootfull cu. Marker `enforced` chi chung
minh CI, Makefile va artifact co the mang dung mode den moi binary. Enforcement
that bat dau o phase tich hop verifier.

## Contract

- Contract version: `1`.
- Feature: `automation`, `stream`, `script`, `admin`, `shell`.
- Task exempt: `60`, `75`, `76`, `96`, `97`, `99`.
- Deny response danh cho phase sau:
  `-1;;license_required component/task feature state error`.
- Inventory may doc tai `license-rootfull-policy.json`.

Diagnostic Phase 0:

- `60`: giu response JSON base64 cu va them contract/build metadata.
- `75`: tra mode build, `state=not_integrated`, `marker_only=1`.
- `76`: reload no-op, generation `0`.
- `96`: thoat `tlinkautod` de LaunchDaemon khoi dong lai.
- `97`: capability/build report rootfull.
- `99`: ping `tlinkauto_alive`.

## Khoang trong rootfull da ghi nhan

Phase 0 co tinh khong sua hanh vi automation ngoai diagnostic:

- `16/17` duoc daemon route nhung khong co nhanh dispatch trong `Task.xm`.
- `72` moi chi duoc khai bao, chua route va chua dispatch.
- `13/18/71` co implementation trong SpringBoard/in-process nhung port `6000`
  khong route den SpringBoard.

Nhung muc nay nam trong `known_transport_gaps` de phase sau khong nham la da
ho tro day du.

## Bao mat

Checker HTTP plaintext cu trong `pccontrol/Tweak.xm` da bi loai bo. Private
signing JWK va admin token khong duoc phep xuat hien trong source/artifact.
Public key Worker duoc them tu Phase 1; private signing key va admin token van
khong duoc dua vao artifact.

Phase 0 khong giai quyet:

- Signed lease verification trong rootfull process.
- Feature gate tai task, H264, script/helper va UI.
- Client authentication cho port automation.
- OLLVM/anti-hook/integrity hardening.

## Kiem tra

Static contract:

```sh
node scripts/check-rootfull-license-phase0.mjs
```

Artifact validator Phase 0 chi giu de kiem tra fixture/goi lich su. Build hien
tai phai dung validator Phase 2:

```sh
node scripts/validate-rootfull-license-phase2-artifact.mjs \
  --rootfs build/rootfull-rootfs \
  --mode observe \
  --endpoint https://license.example.com \
  --keyId example-key-id \
  --publicKeyX <base64url-p256-x> \
  --publicKeyY <base64url-p256-y> \
  --output rootfull-license-phase2-observe.json
```
