/* Giữ tài khoản gốc; chỉ xóa demo.nv01..demo.nv06 chưa có dữ liệu liên quan.
   Không đổi cấu trúc bảng, không sửa mật khẩu, không chuyển đơn sang nhân viên khác.
   Lần đầu để @ThucHien=0 xem trước. Đổi thành 1 rồi chạy lại nếu muốn thực hiện.
   Chọn đúng database của ứng dụng trong SSMS trước khi chạy. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ThucHien bit=0;
IF DB_NAME() IN (N'master',N'model',N'msdb',N'tempdb')
    THROW 51000,N'Hãy chọn database của ứng dụng trong SSMS trước khi chạy.',1;
DECLARE @NvId int,@PqId int,@Nv nvarchar(517),@Pq nvarchar(517);
IF (SELECT COUNT(*) FROM sys.tables WHERE name IN (N'NhanVien',N'NhanViens'))<>1
    THROW 51001,N'Không xác định được duy nhất bảng NhanVien. Dừng, chưa có thay đổi.',1;
IF (SELECT COUNT(*) FROM sys.tables WHERE name IN (N'PhanQuyen',N'PhanQuyens'))<>1
    THROW 51002,N'Không xác định được duy nhất bảng PhanQuyen. Dừng, chưa có thay đổi.',1;
SELECT @NvId=object_id,@Nv=QUOTENAME(SCHEMA_NAME(schema_id))+N'.'+QUOTENAME(name) FROM sys.tables WHERE name IN (N'NhanVien',N'NhanViens');
SELECT @PqId=object_id,@Pq=QUOTENAME(SCHEMA_NAME(schema_id))+N'.'+QUOTENAME(name) FROM sys.tables WHERE name IN (N'PhanQuyen',N'PhanQuyens');
IF EXISTS(SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id=@PqId)
    THROW 51003,N'PhanQuyen có bảng phụ thuộc; cần kiểm tra riêng, chưa có thay đổi.',1;
IF EXISTS(SELECT 1 FROM sys.triggers WHERE parent_id IN (@NvId,@PqId) AND is_disabled=0 AND OBJECTPROPERTY(object_id,'ExecIsDeleteTrigger')=1)
    THROW 51004,N'Có trigger DELETE trên bảng cần dọn. Cần kiểm tra riêng, chưa có thay đổi.',1;
IF EXISTS(SELECT 1 FROM sys.tables WHERE temporal_type<>0 AND object_id IN (@NvId,@PqId))
    THROW 51005,N'Bảng có lịch sử temporal. Cần kiểm tra riêng, chưa có thay đổi.',1;

DROP TABLE IF EXISTS #UngVien;
DROP TABLE IF EXISTS #DangDung;
CREATE TABLE #UngVien(MaNV smallint PRIMARY KEY,HoTen nvarchar(200),TenDN nvarchar(200));
CREATE TABLE #DangDung(MaNV smallint,Nguon nvarchar(517));
DECLARE @sql nvarchar(max),@Nguon nvarchar(517),@DieuKien nvarchar(max);
BEGIN TRY
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRANSACTION;
    SET @sql=N'INSERT #UngVien SELECT MaNV,CONCAT(HoNV,N'' '',TenNV),TenDN FROM '+@Nv+N' WITH(UPDLOCK,HOLDLOCK) WHERE LTRIM(RTRIM(TenDN)) IN (N''demo.nv01'',N''demo.nv02'',N''demo.nv03'',N''demo.nv04'',N''demo.nv05'',N''demo.nv06'');';
    EXEC sys.sp_executesql @sql;

    -- Kiểm tra mọi khóa ngoại đến nhân viên, kể cả khóa ghép và CASCADE.
    DECLARE fk_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT QUOTENAME(OBJECT_SCHEMA_NAME(f.parent_object_id))+N'.'+QUOTENAME(OBJECT_NAME(f.parent_object_id)),
        STRING_AGG(CONVERT(nvarchar(max),N'x.'+QUOTENAME(COL_NAME(c.parent_object_id,c.parent_column_id))+N'=n.'+QUOTENAME(COL_NAME(c.referenced_object_id,c.referenced_column_id))),N' AND ')
    FROM sys.foreign_keys f JOIN sys.foreign_key_columns c ON c.constraint_object_id=f.object_id
    WHERE f.referenced_object_id=@NvId AND f.parent_object_id<>@PqId
    GROUP BY f.object_id,f.parent_object_id;
    OPEN fk_cursor;
    FETCH NEXT FROM fk_cursor INTO @Nguon,@DieuKien;
    WHILE @@FETCH_STATUS=0
    BEGIN
        SET @sql=N'INSERT #DangDung SELECT DISTINCT u.MaNV,@nguon FROM #UngVien u JOIN '+@Nv+N' n ON n.MaNV=u.MaNV JOIN '+@Nguon+N' x WITH(UPDLOCK,HOLDLOCK) ON '+@DieuKien+N';';
        EXEC sys.sp_executesql @sql,N'@nguon nvarchar(517)',@nguon=@Nguon;
        FETCH NEXT FROM fk_cursor INTO @Nguon,@DieuKien;
    END;
    CLOSE fk_cursor;
    DEALLOCATE fk_cursor;

    -- Kiểm tra riêng 2 bảng đơn hàng, ngay cả khi CSDL cũ chưa khai báo FK.
    DECLARE @Ten sysname;
    DECLARE order_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT name FROM (VALUES(N'DonBH'),(N'DonMH')) t(name);
    OPEN order_cursor;
    FETCH NEXT FROM order_cursor INTO @Ten;
    WHILE @@FETCH_STATUS=0
    BEGIN
        IF (SELECT COUNT(*) FROM sys.tables WHERE name IN (@Ten,@Ten+N's'))<>1
            THROW 51006,N'Không xác định được bảng đơn hàng; dừng để tránh mất liên kết.',1;
        SELECT @Nguon=QUOTENAME(SCHEMA_NAME(schema_id))+N'.'+QUOTENAME(name) FROM sys.tables WHERE name IN (@Ten,@Ten+N's');
        SET @sql=N'INSERT #DangDung SELECT DISTINCT u.MaNV,@nguon FROM #UngVien u JOIN '+@Nguon+N' x WITH(UPDLOCK,HOLDLOCK) ON x.MaNV=u.MaNV;';
        EXEC sys.sp_executesql @sql,N'@nguon nvarchar(517)',@nguon=@Nguon;
        FETCH NEXT FROM order_cursor INTO @Ten;
    END;
    CLOSE order_cursor;
    DEALLOCATE order_cursor;

    SELECT DB_NAME() AS [Database],@ThucHien AS [Thực hiện xóa];
    SELECT u.MaNV AS [Mã nhân viên],u.HoTen AS [Họ tên],u.TenDN AS [Tài khoản],
        CASE WHEN EXISTS(SELECT 1 FROM #DangDung d WHERE d.MaNV=u.MaNV)
            THEN N'GIỮ LẠI: đang có dữ liệu liên quan' ELSE N'CÓ THỂ XÓA: tài khoản mẫu chưa dùng' END AS [Kết quả kiểm tra]
    FROM #UngVien u ORDER BY u.MaNV;
    SELECT DISTINCT u.TenDN AS [Tài khoản cần giữ],d.Nguon AS [Bảng đang liên kết]
    FROM #DangDung d JOIN #UngVien u ON u.MaNV=d.MaNV ORDER BY u.TenDN,d.Nguon;

    IF @ThucHien=0
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT N'CHỈ XEM TRƯỚC, chưa xóa gì. Muốn thực hiện: đổi @ThucHien=1 rồi chạy lại.';
    END
    ELSE
    BEGIN
        -- Chỉ bỏ quyền của các nhân viên thực sự đủ điều kiện xóa.
        SET @sql=N'DELETE p FROM '+@Pq+N' p JOIN #UngVien u ON u.MaNV=p.MaNV WHERE NOT EXISTS(SELECT 1 FROM #DangDung d WHERE d.MaNV=u.MaNV);';
        EXEC sys.sp_executesql @sql;
        SET @sql=N'DELETE n FROM '+@Nv+N' n JOIN #UngVien u ON u.MaNV=n.MaNV WHERE NOT EXISTS(SELECT 1 FROM #DangDung d WHERE d.MaNV=u.MaNV);';
        EXEC sys.sp_executesql @sql;
        COMMIT TRANSACTION;
        PRINT N'Đã xóa tài khoản mẫu chưa dùng. Tài khoản gốc và nhân viên đang có dữ liệu được giữ nguyên.';
    END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    THROW;
END CATCH;
-- Không chạy lại 01_DuLieuMau.sql sau khi dọn nếu không muốn tạo lại nhân viên mẫu.
