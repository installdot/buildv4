#import <Foundation/Foundation.h>

// ─── Spoofed Maintenance Response ──────────────────────────────────────────

static NSString *const kMaintenanceResponseJSON = @"{\"isMaintenance\":false}";

// ─── Spoofed Firebase Remote Config Response (full) ────────────────────────

static NSString *getFirebaseResponseJSON() {
    // Full entries from spoofed config
    NSString *congPhapStore = @"[{\"congPhapId\":\"CongPhap_3_AmDuongHop\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_BanNhuocQuyet\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_CapTocThiPhap\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ChienNoHong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ChuyenChu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ChuyenGiaQuanSu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_CongVaThu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_CuongThietTri\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_CuuThanCong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_CuuTieuKinh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_DaoTuNhien\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_DichCanKinh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_DieuKienPhanXa\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_DieuTuc\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_DuongSinhDao\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_GioiPhanKich\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_GioiTrungKich\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_HoaDanThuat\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_HoaLuyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_HoanHonChu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_HoiMaPhap\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_HungTuongLuc\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_KhiNguHanh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_KhiTrieuNguyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_KichChinhXac\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_KienTrangThan\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_KimCangCong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_KimCangThe\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_LinhThuChienDau\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_LinhThuSinhTon\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_LinhTinhCanCo\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_LoiLuyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_LongTuongCong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_LucNguHanh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_LuyenKhiThuat\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_LuyenTheNang\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_MaDaoChienDau\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_MaLucTang\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_MaPhapHoc\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_MaPhapHoiLo\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_MaPhapLuyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_MaPhapThienPhu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_MaPhapThu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_MinhThanCong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_NeTranh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_NguHanhThuat\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_NguKiemThuat\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_NguyenHoThe\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_NguyenQuyNhat\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_PhaLongTram\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_PhapLucTang\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_PhapThuatCucHieu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_PhapThuatThuc\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_PhapThuatXuyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_PhongLuyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_PhongThuPhanKich\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_QuyAnh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_SungHiepThu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_SungKheUoc\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_TamHoaTu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThanBiHoc\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThanGiangLam\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThanQuyNguyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThanhNguyenKiemQuyetAnh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThanhThaoVuKhi\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThauMaPhap\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThienTamCong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThoLuyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThuatChienTranh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThuatChuyenCong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThuatTruongSinh\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_ThuyLuyen\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_TienLucThongNgu\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_TienPhongThuat\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_TienThienKhi\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_TienVoCong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_TuDienCong\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_TuongBangThuat\",\"price\":100,\"priceType\":1},{\"congPhapId\":\"CongPhap_3_TuongGiapCong\",\"price\":100,\"priceType\":1}]";

    NSDictionary *entries = @{
        @"cong_phap_store": congPhapStore,
        @"day_per_bi_canh_area": @"1",
        @"enable_giftcode_button": @"true",
        @"enable_recharge_milestone": @"true",
        @"game_notification": @"{\"enable\":true,\"content\":\"Hacked Client By F4CK Mochi\",\"url_require\":\"https://zalo.me/g/mwdtaq765\"}",
        @"max_cultivation": @"5",
        @"required_client_contains_version": @"0.0.4-0.0.5",
        @"required_client_version": @"0.0.1"
    };

    NSDictionary *root = @{
        @"entries": entries,
        @"appName": @"com.playmoon.thienmadao.ios",
        @"state": @"UPDATE",
        @"templateVersion": @"98"
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

// ─── URL matching helpers ───────────────────────────────────────────────────

static BOOL isFirebaseRCURL(NSURL *url) {
    return [url.host containsString:@"firebaseremoteconfig.googleapis.com"] &&
           [url.path containsString:@"thienmadao-4d4f1"];
}

static BOOL isMaintenanceURL(NSURL *url) {
    return [url.host containsString:@"tmd-game.duckdns.org"] &&
           [url.path containsString:@"maintenance"];
}

// ─── Build a fake HTTP 200 response ────────────────────────────────────────

static void buildFakeResponse(NSURL *url,
                               NSString *jsonBody,
                               NSURLResponse **outResponse,
                               NSData **outData) {
    NSDictionary *headers = @{ @"Content-Type": @"application/json; charset=utf-8" };
    *outResponse = [[NSHTTPURLResponse alloc] initWithURL:url
                                               statusCode:200
                                              HTTPVersion:@"HTTP/1.1"
                                             headerFields:headers];
    *outData = [jsonBody dataUsingEncoding:NSUTF8StringEncoding];
}

// ─── Hook NSURLSession ──────────────────────────────────────────────────────

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    NSURL *url = request.URL;

    if (completionHandler) {
        if (isFirebaseRCURL(url)) {
            NSLog(@"[TMD-Tweak] Firebase RC intercepted → injecting spoofed config");
            NSString *fakeJSON = getFirebaseResponseJSON();
            return %orig(request, ^(NSData *d, NSURLResponse *r, NSError *e) {
                NSData *fakeData = nil; NSURLResponse *fakeResp = nil;
                buildFakeResponse(url, fakeJSON, &fakeResp, &fakeData);
                completionHandler(fakeData, fakeResp, nil);
            });
        }

        if (isMaintenanceURL(url)) {
            NSLog(@"[TMD-Tweak] Maintenance check intercepted → isMaintenance = false");
            return %orig(request, ^(NSData *d, NSURLResponse *r, NSError *e) {
                NSData *fakeData = nil; NSURLResponse *fakeResp = nil;
                buildFakeResponse(url, kMaintenanceResponseJSON, &fakeResp, &fakeData);
                completionHandler(fakeData, fakeResp, nil);
            });
        }
    }

    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithURL:(NSURL *)url
                        completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (completionHandler && isMaintenanceURL(url)) {
        NSLog(@"[TMD-Tweak] Maintenance (URL variant) intercepted → isMaintenance = false");
        return %orig(url, ^(NSData *d, NSURLResponse *r, NSError *e) {
            NSData *fakeData = nil; NSURLResponse *fakeResp = nil;
            buildFakeResponse(url, kMaintenanceResponseJSON, &fakeResp, &fakeData);
            completionHandler(fakeData, fakeResp, nil);
        });
    }
    return %orig;
}

%end
