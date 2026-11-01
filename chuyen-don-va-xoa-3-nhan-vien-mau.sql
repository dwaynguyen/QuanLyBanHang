/* Da duoc dong y:
   demo.nv01 -> tandat; demo.nv02 -> vanan; demo.nv04 -> quocbao.
   Chuyen nhan vien phu trach tren DonBH/DonMH; khong thay doi san pham, gia, so luong.
   Xoa quyen va 3 nhan vien mau sau khi chuyen; giu quyen/mat khau nhan vien goc.
   Sao luu database truoc khi chay neu can khoi phuc lich su nhan vien cu.
   Mo file RIENG trong SSMS, Ctrl+A va F5. Mac dinh THUC HIEN theo xac nhan.
   Co the doi @ThucHien=0 de chi xem truoc. */
USE [DbQLBH];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @ThucHien bit = 1;
DECLARE @Ten TABLE (Nguon nvarchar(50) PRIMARY KEY, Dich nvarchar(50) NOT NULL);
INSERT INTO @Ten VALUES
    (N'demo.nv01', N'tandat'),
    (N'demo.nv02', N'vanan'),
    (N'demo.nv04', N'quocbao');
DECLARE @NhanVien TABLE (MaNV smallint PRIMARY KEY, TenDN nvarchar(200));
DECLARE @Map TABLE (Nguon nvarchar(50) PRIMARY KEY, Dich nvarchar(50), MaCu smallint, MaMoi smallint NOT NULL);
DECLARE @DonBan bigint, @DonMua bigint, @CanChuyenBan bigint, @CanChuyenMua bigint;
DECLARE @DaChuyenBan bigint = 0, @DaChuyenMua bigint = 0, @DaXoaNhanVien int = 0;

-- Dung thay vi tu dong tac dong cac lien ket khong duoc phe duyet.
IF OBJECT_ID(N'dbo.NhanVien', N'U') IS NULL OR OBJECT_ID(N'dbo.PhanQuyen', N'U') IS NULL
   OR OBJECT_ID(N'dbo.DonBH', N'U') IS NULL OR OBJECT_ID(N'dbo.DonMH', N'U') IS NULL
BEGIN
    RAISERROR(N'Thieu bang dbo.NhanVien/PhanQuyen/DonBH/DonMH. Dung, chua thay doi gi.', 16, 1);
    RETURN;
END;
IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE referenced_object_id = OBJECT_ID(N'dbo.NhanVien')
      AND parent_object_id NOT IN (OBJECT_ID(N'dbo.DonBH'), OBJECT_ID(N'dbo.DonMH'), OBJECT_ID(N'dbo.PhanQuyen'))
)
OR EXISTS (SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id = OBJECT_ID(N'dbo.PhanQuyen'))
BEGIN
    RAISERROR(N'Co bang phu thuoc khac can kiem tra rieng. Dung, chua thay doi gi.', 16, 1);
    RETURN;
END;
IF EXISTS (
    SELECT 1 FROM sys.foreign_key_columns c
    WHERE c.referenced_object_id = OBJECT_ID(N'dbo.NhanVien')
      AND (COL_NAME(c.parent_object_id, c.parent_column_id) <> N'MaNV'
           OR COL_NAME(c.referenced_object_id, c.referenced_column_id) <> N'MaNV')
)
BEGIN
    RAISERROR(N'Co khoa ngoai nhan vien khong theo MaNV. Dung de kiem tra rieng.', 16, 1);
    RETURN;
END;
IF EXISTS (
    SELECT 1 FROM sys.triggers
    WHERE parent_id IN (OBJECT_ID(N'dbo.NhanVien'), OBJECT_ID(N'dbo.PhanQuyen'), OBJECT_ID(N'dbo.DonBH'), OBJECT_ID(N'dbo.DonMH'))
      AND is_disabled = 0
)
BEGIN
    RAISERROR(N'Co trigger tren bang can cap nhat. Can kiem tra rieng, chua thay doi gi.', 16, 1);
    RETURN;
END;

BEGIN TRY
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRANSACTION;

    INSERT INTO @NhanVien (MaNV, TenDN)
    SELECT n.MaNV, LTRIM(RTRIM(n.TenDN))
    FROM dbo.NhanVien n WITH (UPDLOCK, HOLDLOCK)
    WHERE LTRIM(RTRIM(n.TenDN)) IN (SELECT Nguon FROM @Ten UNION SELECT Dich FROM @Ten);

    IF EXISTS (SELECT TenDN FROM @NhanVien GROUP BY TenDN HAVING COUNT(*) > 1)
        RAISERROR(N'Trung ten dang nhap nhan vien. Dung, giao dich se hoan tac.', 16, 1);
    IF EXISTS (SELECT 1 FROM @Ten t WHERE NOT EXISTS (SELECT 1 FROM @NhanVien n WHERE n.TenDN=t.Dich))
        RAISERROR(N'Thieu tai khoan dich tandat/vanan/quocbao. Dung, giao dich se hoan tac.', 16, 1);

    INSERT INTO @Map (Nguon, Dich, MaCu, MaMoi)
    SELECT t.Nguon, t.Dich, s.MaNV, d.MaNV
    FROM @Ten t
    LEFT JOIN @NhanVien s ON s.TenDN=t.Nguon
    INNER JOIN @NhanVien d ON d.TenDN=t.Dich;

    IF EXISTS (SELECT 1 FROM @Map WHERE MaCu=MaMoi)
        RAISERROR(N'Ma nhan vien nguon trung ma dich. Dung.', 16, 1);

    SELECT @DonBan=COUNT_BIG(*) FROM dbo.DonBH WITH (HOLDLOCK);
    SELECT @DonMua=COUNT_BIG(*) FROM dbo.DonMH WITH (HOLDLOCK);
    SELECT @CanChuyenBan=COUNT_BIG(*) FROM dbo.DonBH b WITH (UPDLOCK,HOLDLOCK) JOIN @Map m ON m.MaCu=b.MaNV;
    SELECT @CanChuyenMua=COUNT_BIG(*) FROM dbo.DonMH d WITH (UPDLOCK,HOLDLOCK) JOIN @Map m ON m.MaCu=d.MaNV;

    SELECT m.Nguon AS [Tai khoan mau],m.Dich AS [Chuyen sang],m.MaCu AS [Ma cu],m.MaMoi AS [Ma moi],
        (SELECT COUNT_BIG(*) FROM dbo.DonBH b WHERE b.MaNV=m.MaCu) AS [So don ban],
        (SELECT COUNT_BIG(*) FROM dbo.DonMH d WHERE d.MaNV=m.MaCu) AS [So don mua],
        CASE WHEN m.MaCu IS NULL THEN N'Da xoa truoc do - khong lam gi' ELSE N'Se chuyen don va xoa tai khoan mau' END AS [Thao tac]
    FROM @Map m ORDER BY m.Nguon;

    IF @ThucHien=1
    BEGIN
        UPDATE b SET MaNV=m.MaMoi
        FROM dbo.DonBH b JOIN @Map m ON m.MaCu=b.MaNV;
        SET @DaChuyenBan=@@ROWCOUNT;

        UPDATE d SET MaNV=m.MaMoi
        FROM dbo.DonMH d JOIN @Map m ON m.MaCu=d.MaNV;
        SET @DaChuyenMua=@@ROWCOUNT;

        IF @DaChuyenBan<>@CanChuyenBan OR @DaChuyenMua<>@CanChuyenMua
            RAISERROR(N'So dong cap nhat khong khop. Dung va hoan tac.',16,1);
        IF EXISTS(SELECT 1 FROM dbo.DonBH b JOIN @Map m ON m.MaCu=b.MaNV)
           OR EXISTS(SELECT 1 FROM dbo.DonMH d JOIN @Map m ON m.MaCu=d.MaNV)
            RAISERROR(N'Van con don gan voi nhan vien mau. Dung va hoan tac.',16,1);

        DELETE p FROM dbo.PhanQuyen p JOIN @Map m ON m.MaCu=p.MaNV;
        DELETE n FROM dbo.NhanVien n JOIN @Map m ON m.MaCu=n.MaNV;
        SET @DaXoaNhanVien=@@ROWCOUNT;

        IF (SELECT COUNT_BIG(*) FROM dbo.DonBH)<>@DonBan OR (SELECT COUNT_BIG(*) FROM dbo.DonMH)<>@DonMua
            RAISERROR(N'So luong don hang thay doi bat thuong. Dung va hoan tac.',16,1);
        IF EXISTS(SELECT 1 FROM dbo.NhanVien n JOIN @Map m ON m.MaCu=n.MaNV)
            RAISERROR(N'Van con tai khoan mau can xoa. Dung va hoan tac.',16,1);

        COMMIT TRANSACTION;
        SELECT @DaChuyenBan AS [Don ban da chuyen],@DaChuyenMua AS [Don mua da chuyen],@DaXoaNhanVien AS [Nhan vien mau da xoa];
        PRINT N'THANH CONG: da chuyen don theo dung bang da dong y va xoa tai khoan mau. Khong thay doi cau truc bang.';
    END
    ELSE
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT N'CHI XEM TRUOC. Chua cap nhat hoac xoa du lieu.';
    END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END TRY
BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    DECLARE @Loi nvarchar(2048)=ERROR_MESSAGE();
    RAISERROR(N'%s',16,1,@Loi);
END CATCH;
GO
-- Khong hien thi MatKhau.
SELECT MaNV AS [Ma nhan vien],CONCAT(HoNV,N' ',TenNV) AS [Ho ten],TenDN AS [Tai khoan con lai]
FROM dbo.NhanVien ORDER BY MaNV;
GO
-- Khong chay lai 01_DuLieuMau.sql sau khi don neu khong muon tao lai tai khoan demo.
