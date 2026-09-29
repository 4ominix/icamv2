# FakeCameraWeat

Một tweak hoàn thiện dành cho thiết bị iOS (Jailbreak / Rootless / Rootful) can thiệp sâu vào hệ thống camera (`AVFoundation`, `CoreMedia`, `mediaserverd`) để thay thế luồng video và ảnh chụp thật bằng hình ảnh hoặc video giả lập do người dùng chọn trực tiếp từ Thư viện ảnh (Photos).

Tweak hoạt động xuyên suốt hệ sinh thái iOS (**system-wide**), áp dụng cho:
- Ứng dụng **Camera mặc định** của Apple (cả chế độ video và chụp ảnh tĩnh).
- Các ứng dụng mạng xã hội & gọi video: Zalo, Facebook Messenger, Telegram, TikTok, Instagram.
- Các ứng dụng ngân hàng, định danh trực tuyến (eKYC) và nhận diện khuôn mặt.

---

## 🎯 3 Tính Năng Cốt Lõi Được Tích Hợp

1. **Công tắc Bật/Tắt Thời Gian Thực:**
   - Điều khiển trực tiếp trong Cài Đặt (Settings).
   - Tự động phát tín hiệu `Darwin Notification` (`com.weat.fakecamera/prefsupdated`) đến tất cả tiến trình đang chạy để kích hoạt hoặc trả lại camera gốc ngay lập tức mà không cần respring.
2. **Chọn Hình Ảnh Trực Tiếp Tại Thư Viện (Photo Picker):**
   - Nút **"📷 Chọn Ảnh Tại Thư Viện"** trong Settings cho phép mở `UIImagePickerController` truy cập Thư Viện Ảnh (Photos).
   - Tự động nạp, tối ưu kích thước, lưu vào bộ nhớ cục bộ `/var/mobile/Documents/FakeCamera/fake_image.jpg` và đồng bộ cấu hình.
3. **Chọn Video Trực Tiếp Tại Thư Viện (Video Picker):**
   - Nút **"🎬 Chọn Video Tại Thư Viện"** trong Settings cho phép chọn bất kỳ video nào có sẵn trong Photos.
   - Sao chép vào đường dẫn chuẩn `/var/mobile/Documents/FakeCamera/fake_video.mp4`, tự động lặp lại (loop vô hạn) không giật lag.

---

## 📂 Cấu Trúc Toàn Bộ Dự Án

```text
FakeCameraWeat/
├── Makefile                                        # Cấu hình biên dịch chính của Theos (Clang, Frameworks: AVFoundation, CoreMedia, CoreVideo, CoreGraphics)
├── FakeCameraWeat.plist                            # Filter định tuyến hook: com.apple.camera, com.apple.UIKit, com.apple.AVFoundation, mediaserverd
├── control                                         # Thông tin gói deb (Package: com.weat.fakecamera)
├── Tweak.x                                         # Core hooking logic (AVCaptureVideoDataOutput, AVCapturePhotoOutput, AVCapturePhoto, CVPixelBuffer)
├── README.md                                       # Tài liệu hướng dẫn chi tiết
├── layout/
│   └── Library/
│       └── PreferenceLoader/
│           └── Preferences/
│               └── FakeCameraWeat.plist            # Điểm neo mục "Fake Camera" hiển thị trong Settings của iOS
└── FakeCameraPrefs/                                # PreferenceBundle giao diện điều khiển
    ├── Makefile                                    # Cấu hình build bundle settings (UIKit, MobileCoreServices, Photos, Preferences)
    ├── FakeCameraPrefsRootListController.m         # Controller xử lý chọn ảnh/video từ thư viện, phân quyền Photos và lưu file
    └── Resources/
        └── Root.plist                              # Định nghĩa giao diện mục cài đặt
```

---

## ⚙️ Cơ Chế Hoạt Động & Tối Ưu Chuyên Sâu

### 1. Luồng Video Trực Tiếp (`AVCaptureVideoDataOutput`)
- Swizzle delegate `captureOutput:didOutputSampleBuffer:fromConnection:`.
- Lấy con trỏ `CMSampleBufferRef` nguyên bản để kế thừa chính xác tem thời gian PTS (`presentationTimeStamp`), đảm bảo video khớp fps và âm thanh đồng bộ tuyệt đối.
- Bọc lại buffer giả bằng `CMSampleBufferCreateReadyWithImageBuffer` và giải phóng triệt để qua `CFRelease` / `CVPixelBufferRelease`, tránh 100% memory leak.

### 2. Chụp Ảnh Tĩnh (`AVCapturePhotoOutput` & `AVCapturePhoto`)
- Hook `capturePhotoWithSettings:delegate:` và `AVCapturePhoto`.
- Ghi đè phương thức `-pixelBuffer` và `-fileDataRepresentation` của `AVCapturePhoto` để khi người dùng hoặc ứng dụng bấm nút chụp ảnh (shutter), ảnh trả về chính là file ảnh/frame video giả lập thay vì cảm biến phần cứng thật.

### 3. Đồng Bộ Đa Luồng & An Toàn Bộ Nhớ
- Toàn bộ thao tác tạo buffer tĩnh (`staticImageBuffer`) và luồng video (`AVPlayerItemVideoOutput`) đều được bảo vệ bởi khóa đồng bộ `pthread_mutex_t mediaLock`. Không bao giờ bị race condition hay crash khi nhiều camera/app gọi đồng thời.

---

## 🛠 Hướng Dẫn Biên Dịch & Cài Đặt

1. Đảm bảo máy Mac hoặc môi trường build đã cài đặt Theos.
2. Mở Terminal tại thư mục này và chạy:
   ```bash
   make clean
   make package FINALPACKAGE=1
   ```
3. Cài file `.deb` sinh ra trong thư mục `packages/` qua Filza, Sileo, hoặc Zebra.
4. Vào **Cài Đặt (Settings) -> Fake Camera**:
   - Chọn ảnh hoặc video từ thư viện của máy.
   - Bật công tắc **Bật Fake Camera**.
   - Mở ứng dụng Camera hoặc bất kỳ app nào để tận hưởng.
