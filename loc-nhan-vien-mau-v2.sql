USE [DbQLBH];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- 0 = xem truoc; 1 = xoa cac tai khoan mau CHUA co don hang.
DECLARE @ThucHien bit = 0;
DECLARE @Xoa TABLE (MaNV smallint PRIMARY KEY);

-- Chi ho tro cac bang dbo ben duoi. Dung neu co lien ket/trigger khac.
IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE referenced_object_id = OBJECT_ID(N'dbo.NhanVien')
      AND parent_object_id NOT IN (
          OBJECT_ID(N'dbo.DonBH'), OBJECT_ID(N'dbo.DonMH'), OBJECT_ID(N'dbo.PhanQuyen')
      )
)
BEGIN
    RAISERROR(N'NhanVien co bang phu thuoc khac. Can kiem tra rieng, chua xoa gi.', 16, 1);
    RETURN;
END;
IF EXISTS (SELECT 1 FROM sys.foreign_keys WHERE referenced_object_id = OBJECT_ID(N'dbo.PhanQuyen'))
BEGIN
    RAISERROR(N'PhanQuyen co bang phu thuoc. Can kiem tra rieng, chua xoa gi.', 16, 1);
    RETURN;
END;
IF EXISTS (
    SELECT 1 FROM sys.triggers
    WHERE parent_id IN (OBJECT_ID(N'dbo.NhanVien'), OBJECT_ID(N'dbo.PhanQuyen'))
      AND is_disabled = 0 AND OBJECTPROPERTY(object_id, 'ExecIsDeleteTrigger') = 1
)
BEGIN
    RAISERROR(N'Co trigger DELETE. Can kiem tra rieng, chua xoa gi.', 16, 1);
    RETURN;
END;

BEGIN TRY
    SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    BEGIN TRANSACTION;

    INSERT INTO @Xoa (MaNV)
    SELECT n.MaNV
    FROM dbo.NhanVien AS n WITH (UPDLOCK, HOLDLOCK)
    WHERE LTRIM(RTRIM(n.TenDN)) IN (
        N'demo.nv01', N'demo.nv02', N'demo.nv03',
        N'demo.nv04', N'demo.nv05', N'demo.nv06'
    )
      AND NOT EXISTS (SELECT 1 FROM dbo.DonBH AS b WITH (UPDLOCK, HOLDLOCK) WHERE b.MaNV = n.MaNV)
      AND NOT EXISTS (SELECT 1 FROM dbo.DonMH AS m WITH (UPDLOCK, HOLDLOCK) WHERE m.MaNV = n.MaNV);

    SELECT n.MaNV AS [Ma nhan vien], CONCAT(n.HoNV, N' ', n.TenNV) AS [Ho ten], n.TenDN AS [Tai khoan],
           CASE WHEN x.MaNV IS NULL THEN N'GIU LAI: dang co don hang'
                ELSE N'CO THE XOA: tai khoan mau chua dung' END AS [Ket qua]
    FROM dbo.NhanVien AS n
    LEFT JOIN @Xoa AS x ON x.MaNV = n.MaNV
    WHERE LTRIM(RTRIM(n.TenDN)) IN (
        N'demo.nv01', N'demo.nv02', N'demo.nv03',
        N'demo.nv04', N'demo.nv05', N'demo.nv06'
    )
    ORDER BY n.MaNV;

    IF @ThucHien = 1
    BEGIN
        DELETE p
        FROM dbo.PhanQuyen AS p
        INNER JOIN @Xoa AS x ON x.MaNV = p.MaNV;

        DELETE n
        FROM dbo.NhanVien AS n
        INNER JOIN @Xoa AS x ON x.MaNV = n.MaNV;

        COMMIT TRANSACTION;
        PRINT N'Da xoa nhan vien mau chua dung. Khong doi mat khau, quyen cua nhan vien goc hoac cau truc bang.';
    END
    ELSE
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT N'CHI XEM TRUOC. Muon xoa, doi @ThucHien = 1 roi chay lai TOAN BO file.';
    END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    DECLARE @Loi nvarchar(2048) = ERROR_MESSAGE();
    RAISERROR(N'%s', 16, 1, @Loi);
END CATCH;
GO
-- Khong chay lai script du lieu mau neu khong muon tao lai tai khoan demo.
