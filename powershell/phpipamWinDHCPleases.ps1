# -----------------------------
# TUYÊN BỐ MIỄN TRỪ TRÁCH NHIỆM PHÁP LÝ
# -----------------------------
# Script này được cung cấp "nguyên trạng" (as is) và không kèm theo bất kỳ bảo đảm
# rõ ràng hay ngụ ý nào, bao gồm nhưng không giới hạn ở bảo đảm về khả năng thương mại
# hoặc sự phù hợp cho một mục đích cụ thể.
# Tác giả không chịu trách nhiệm cho bất kỳ thiệt hại hoặc mất dữ liệu nào phát sinh
# trực tiếp hoặc gián tiếp từ việc sử dụng script này.
# Người sử dụng phải tự kiểm tra, đánh giá và chỉnh sửa script trước khi triển khai
# trong môi trường production.
# Script này chỉ phục vụ mục đích học tập và tham khảo. Tự chịu rủi ro khi sử dụng.

# -----------------------------
# MỤC ĐÍCH CỦA SCRIPT
# -----------------------------
# Mục đích chính của script này là đồng bộ DHCP lease từ Windows DHCP Server
# sang hệ thống quản lý IP phpIPAM.
# Script sẽ lấy toàn bộ DHCP lease từ Windows DHCP Server và cập nhật IP tương ứng
# vào phpIPAM để đảm bảo dữ liệu phpIPAM phản ánh đúng trạng thái DHCP hiện tại.
# Có thể tùy chọn cập nhật custom field trong phpIPAM (ví dụ: lease duration, trạng thái thiết bị).
# Đảm bảo các custom field này đã được tạo sẵn trong phpIPAM.

# -----------------------------
# TÓM TẮT CHỨC NĂNG
# -----------------------------
# 1. Lấy toàn bộ DHCP lease trong các scope từ Windows DHCP Server
# 2. Cập nhật thông tin IP vào phpIPAM
#    - Script có thể chạy thủ công hoặc theo lịch (Windows Task Scheduler)
#    - Có thể chạy trực tiếp trên DHCP Server hoặc máy khác có quyền truy cập
# 3. (Tùy chọn) Ghi log toàn bộ hoạt động để audit và debug
# 4. (Tùy chọn) Ping kiểm tra IP trước khi thêm vào phpIPAM

# -----------------------------
# HƯỚNG DẪN CẤU HÌNH
# -----------------------------
# Yêu cầu để script hoạt động:
# 1. phpIPAM API Base URL, Section ID và API Token
# 2. Script phải chạy trên máy có quyền Admin và truy cập được DHCP Server
# 3. Timeout API: 5 giây cho mỗi request đến phpIPAM
#    - Cấu hình trong hàm kiểm tra IP tồn tại
# 4. Logging:
#    - $logToFile = $true để bật ghi log
#    - Ghi log có thể làm giảm hiệu năng khi xử lý nhiều lease
#    - Khuyến nghị tắt logging trong production

# -----------------------------
# CHẠY DƯỚI DẠNG SCHEDULED TASK
# -----------------------------
# 1. Mở Task Scheduler
# 2. Tạo New Task
# 3. Thiết lập trigger (ví dụ: hourly, daily)
# 4. Action: Start a program
#    - Program: powershell.exe
#    - Arguments: -File C:\path\to\script.ps1
# 5. Chạy bằng tài khoản có đủ quyền DHCP + phpIPAM

# -----------------------------
# CẤU HÌNH phpIPAM API
# -----------------------------
$apiBase = "https://yourservernameorip/api/appcode"
$token = "yourtokengoeshere"
$sectionId = YourSection#

# -----------------------------
# CÁC TUỲ CHỌN
# -----------------------------
$descriptionPrefix = "Imported from WIN DHCP"  # Tiền tố mô tả cho IP trong phpIPAM
$useFullHostname = $false                      # $false = cắt hostname trước dấu .
$checkHost = $false                            # $true = ping kiểm tra IP trước khi add (chậm)

# -----------------------------
# CẤU HÌNH LOG
# -----------------------------
$logToFile = $false  # $true = ghi log ra file

# -----------------------------
# BỎ QUA KIỂM TRA SSL (CHỈ DÙNG KHI CERT TỰ KÝ)
# -----------------------------
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# -----------------------------
# ÉP SỬ DỤNG TLS 1.2
# -----------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -----------------------------
# HÀM GHI LOG
# -----------------------------
function Write-Log {
    param (
        [string]$message,
        [bool]$logToFile = $false,
        [string]$logFile = "C:\logs\phpipam_script.log"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $message"
    Write-Host $logMessage

    if ($logToFile) {
        $logDirectory = [System.IO.Path]::GetDirectoryName($logFile)
        if (-not (Test-Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force
        }
        Add-Content -Path $logFile -Value $logMessage
    }
}

# -----------------------------
# KIỂM TRA IP CÓ TỒN TẠI TRONG phpIPAM KHÔNG
# -----------------------------
function Get-IPAddressFromPhpIPAM {
    param (
        [string]$ipAddress,
        [bool]$logToFile = $false
    )

    Write-Log "Checking if IP $ipAddress exists in phpIPAM..." $logToFile
    $getIpUrl = "$apiBase/addresses/search/$ipAddress/"

    try {
        $request = [System.Net.HttpWebRequest]::Create($getIpUrl)
        $request.Method = "GET"
        $request.Headers.Add("token", $token)
        $request.ContentType = "application/json"
        $request.Timeout = 5000

        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $parsedJson = ($reader.ReadToEnd()) | ConvertFrom-Json

        if ($parsedJson.data) {
            Write-Log "IP $ipAddress found in phpIPAM." $logToFile
            return $parsedJson.data
        } else {
            return $null
        }
    } catch {
        return $null
    }
}

# -----------------------------
# LẤY TOÀN BỘ SUBNET TỪ phpIPAM
# -----------------------------
function Get-AllSubnetsFromPhpIPAM {
    param ([bool]$logToFile = $false)

    $getSubnetsUrl = "$apiBase/sections/$sectionId/subnets/"
    try {
        $request = [System.Net.HttpWebRequest]::Create($getSubnetsUrl)
        $request.Method = "GET"
        $request.Headers.Add("token", $token)
        $request.ContentType = "application/json"

        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        return (Parse-JsonHandlingDuplicates ($reader.ReadToEnd())).data
    } catch {
        return $null
    }
}

# -----------------------------
# XỬ LÝ JSON BỊ TRÙNG KEY
# -----------------------------
function Parse-JsonHandlingDuplicates {
    param ([string]$jsonString)
    $jsonString = $jsonString -replace '"Used":', '"UsedDuplicate":'
    return ($jsonString | ConvertFrom-Json)
}

# -----------------------------
# THÊM IP VÀO phpIPAM
# -----------------------------
function Add-IPToPhpIPAM {
    param (
        [string]$ipAddress,
        [string]$hostname,
        [string]$macAddress,
        [int]$subnetId,
        [bool]$logToFile = $false
    )

    $macAddress = $macAddress -replace '-', ':'
    $ipData = @{
        ip = $ipAddress
        subnetId = $subnetId
        hostname = $hostname
        mac = $macAddress
        description = "$descriptionPrefix - $hostname"
    }

    $request = [System.Net.HttpWebRequest]::Create("$apiBase/addresses/")
    $request.Method = "POST"
    $request.Headers.Add("token", $token)
    $request.ContentType = "application/json"

    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($ipData | ConvertTo-Json))
    $request.GetRequestStream().Write($bytes, 0, $bytes.Length)
    $request.GetResponse() | Out-Null
}

# -----------------------------
# CHẠY XỬ LÝ DHCP LEASE
# -----------------------------
function Process-DhcpLeases {
    param ([bool]$logToFile = $false)

    $subnets = Get-AllSubnetsFromPhpIPAM
    if (-not $subnets) { return }

    $scopes = Get-DhcpServerv4Scope
    foreach ($scope in $scopes) {
        $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId
        foreach ($lease in $leases) {

            if ($lease.AddressState -ne 'Active') { continue }

            $ipAddress = $lease.IPAddress.IPAddressToString
            $hostname = if ($useFullHostname) { $lease.HostName } else { ($lease.HostName -split '\.')[0] }
            $mac = $lease.ClientId

            foreach ($subnet in $subnets) {
                if ($ipAddress.StartsWith($subnet.subnet.Substring(0, $subnet.subnet.LastIndexOf('.')))) {
                    $existing = Get-IPAddressFromPhpIPAM $ipAddress
                    if (-not $existing) {
                        Add-IPToPhpIPAM $ipAddress $hostname $mac $subnet.id
                    }
                    break
                }
            }
        }
    }
}

# -----------------------------
# ĐIỂM CHẠY CHÍNH
# -----------------------------
Process-DhcpLeases -logToFile $logToFile
