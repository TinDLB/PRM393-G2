# Phân công chức năng

## Người 1: Bạn, phụ trách lõi quan trọng

Chịu trách nhiệm về đăng nhập, tài khoản, dữ liệu và các thao tác có rủi ro cao:

- Đăng ký, đăng nhập, đăng xuất, phiên truy cập và đặt lại mật khẩu.
- Thông tin tài khoản và đồng bộ tùy chọn tài khoản.
- Tạo và quản lý kênh; tải lên theo chunk, sửa/xóa video và lưu trữ media.
- Schema SQL Server, truy cập database, cấu hình secrets và middleware/API bootstrap.
- Kiểm soát API contract và migration database.
- Khởi tạo ứng dụng và tích hợp các repository/dịch vụ dùng chung.

**Phần code chính**: `lib/main.dart`, `lib/features/account/**`, `lib/core/network/**`,
`lib/core/storage/**`, các file backend `AuthEndpoints.cs`, `AccountEndpoints.cs`,
`ChannelEndpoints.cs`, `ApiDatabase.cs`, `ChunkedVideoUploadStore.cs`,
`PasswordResetEmailSender.cs`, `Program.cs`, SQL schema, `run.ps1` và README
backend, `test/account_repository_test.dart`.

## Người 2: Các chức năng trải nghiệm xem và tương tác

Chịu trách nhiệm các luồng sản phẩm không thay đổi quy tắc tài khoản, schema hay
lưu trữ lõi:

- Trang chủ, danh mục, tìm kiếm và hiển thị danh sách video.
- Phát video, trang chi tiết video và trang xem kênh.
- Thư viện: video đã thích, xem sau, lịch sử và kênh đăng ký.
- Thông báo; bình luận, trả lời, reaction và báo cáo nội dung.
- Giao diện và theme; test cho các luồng xem video/tương tác.

**Phan code chinh**: `lib/features/youtube/**`, `lib/theme/**`, backend
`VideoEndpoints.cs`, `SocialEndpoints.cs`, `NotificationEndpoints.cs`,
`CommentEndpoints.cs` va `test/backend_youtube_video_repository_test.dart`.

## Ranh giới phối hợp

- Người 1 là owner của API contract, `ApiDatabase.cs`, SQL schema và
  `Program.cs`. Người 2 mô tả nhu cầu endpoint trước khi thay đổi các phần này.
- `main.dart` là điểm tích hợp chung; thay đổi điều hướng hoặc khởi tạo cần
  được Người 1 review, còn UI/theme trong feature thuộc Người 2.
- Người 2 tiêu thụ API qua repository và `BackendApiClient`; nếu cần thêm API
  client hoặc sửa contract thì thống nhất với Người 1 trước.
- `ChannelEndpoints.cs` gồm cả API quản lý kênh và API kênh công khai; Người 1
  giữ ownership file để tránh conflict. Người 2 phụ trách UI xem kênh và gửi
  yêu cầu API qua review.
- Mỗi người sửa test thuộc chức năng mình phụ trách. Thay đổi schema/API cần
  chạy lại test Flutter và build backend trước khi hợp nhất.

## Ghi chú hiện trạng

Backend đã có API bình luận, reaction và report, nhưng Flutter chưa có UI cho
các luồng này. Đây là phần chưa hoàn thiện, không phải code dư; giữ lại cho đến
khi có quyết định loại bỏ tính năng và API contract.