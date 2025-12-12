# -----------------------------
# Tuyên bố miễn trừ trách nhiệm pháp lý:
# -----------------------------
# Script này được cung cấp "nguyên trạng" (as is) và không kèm bất kỳ bảo đảm rõ ràng hay ngụ ý nào,
# bao gồm nhưng không giới hạn ở các bảo đảm ngụ ý về tính thương mại và phù hợp cho một mục đích cụ thể.
# Tác giả không chịu trách nhiệm cho bất kỳ thiệt hại hay mất dữ liệu nào do sử dụng script này,
# dù trực tiếp hay gián tiếp.
# Người dùng có trách nhiệm tự xem xét kỹ, kiểm thử và chỉnh sửa script trước khi triển khai production.
# Script này chỉ nhằm mục đích giáo dục và cung cấp thông tin. Tự chịu rủi ro khi sử dụng.

# -----------------------------
# Mục đích của Script:
# -----------------------------
# Mục đích chính của script này là tích hợp lease từ Microsoft Windows DHCP Server với hệ thống quản lý IP phpIPAM.
# Script lấy toàn bộ DHCP lease từ Windows DHCP server và cập nhật vào phpIPAM,
# đảm bảo database phpIPAM phản ánh đúng trạng thái hiện tại của DHCP server.
# (Tuỳ chọn) Cập nhật custom fields trong phpIPAM, như thời hạn lease hoặc trạng thái thiết bị.
# Đảm bảo các custom fields cần thiết đã được tạo trong phpIPAM để hoạt động đúng.

# Tóm tắt chức năng:
# 1. Lấy toàn bộ DHCP leases trong các scope từ Windows DHCP server.
# 2. Cập nhật phpIPAM bằng thông tin IP.
#       - Script có thể chạy thủ công hoặc lên lịch chạy tự động bằng Windows Task Scheduler
#           trên chính DHCP server hoặc một máy khác có thể truy cập DHCP server qua mạng.
# 3. (Tuỳ chọn) Ghi log mọi thao tác ra file để audit và troubleshoot.
# 4. (Tuỳ chọn) Kiểm tra host (ping) trước khi thêm IP vào phpIPAM.

# -----------------------------
# Hướng dẫn cấu hình:
# -----------------------------
# Các yêu cầu bắt buộc để script chạy:
# 1. phpIPAM API Base URL, Section ID và API Token.
# 2. Script PowerShell phải chạy trên máy có truy cập được Windows DHCP server và cần quyền Admin
# 3. Cấu hình Timeout: script ép timeout 5 giây cho request phpIPAM API. Nếu không nhận được phản hồi trong thời gian này,
#     request sẽ bị coi là thất bại, script sẽ log lỗi và tiếp tục.
#     - Nằm trong "Function to check if an IP address exists in phpIPAM"
# 4. Cấu hình Logging: script hỗ trợ log ra file để audit & troubleshoot. Set $logToFile = $true để bật log ra file. Lưu ý:
#       bật logging có thể ảnh hưởng hiệu năng, nhất là khi xử lý số lượng lease lớn. Cân nhắc tắt logging trong production để tối ưu.

# Chạy dưới dạng Scheduled Task:
# -----------------------------
# Bạn có thể cấu hình script chạy tự động bằng Windows Task Scheduler.
# 1. Mở Task Scheduler.
# 2. Tạo task mới.
# 3. Set trigger theo chu kỳ mong muốn (ví dụ: hourly, daily).
# 4. Set action là "Start a program" và trỏ đến PowerShell (`powershell.exe`).
# 5. Ở arguments, truyền đường dẫn script (ví dụ: `-File C:\path\to\script.ps1`).
# 6. Đảm bảo task chạy dưới account có đủ quyền truy cập cả DHCP server và phpIPAM.

# -----------------------------
# Khai báo phpIPAM API base, section ID và API token
# -----------------------------
$apiBase = "https://yourservernameorip/api/appcode"
$token = "yourtokengoeshere"
$sectionId = YourSection#

# Các cờ tuỳ chọn (feature flags)
$descriptionPrefix = "Imported from WIN DHCP"  # Đặt tiền tố mô tả cho IP và subnet entries trong phpIPAM.
$useFullHostname = $false  # Set $false để dùng hostname rút gọn (phần trước dấu chấm đầu tiên)
$checkHost = $false  # Host Check (Ping): script có tuỳ chọn ping kiểm tra trước khi add mỗi IP vào phpIPAM.
                        # Bật ($checkHost = $true) sẽ kiểm tra IP có phản hồi trước khi tiếp tục. Lưu ý:
                        # bật tuỳ chọn này có thể tăng đáng kể thời gian xử lý tổng thể, nhất là với số lượng lease lớn,
                        # vì mỗi IP sẽ bị ping riêng lẻ.

# Cấu hình logging
$logToFile = $false  # Bật/tắt log ra file (set $true để bật)

# Tắt kiểm tra SSL certificate (chỉ khi cần cho self-signed cert)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Ép dùng TLS 1.2 để giao tiếp an toàn với phpIPAM API.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -----------------------------
# Hàm log: ghi ra console và (tuỳ chọn) ghi ra file, kèm logging bổ sung
# Lưu ý quan trọng về Logging: bật log ra file ($logToFile = $true) có thể tăng I/O disk đáng kể, nhất là khi
#    script xử lý nhiều DHCP lease. Khuyến nghị chỉ bật khi debug/audit và tắt trong production để tăng hiệu năng.
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
        # Đảm bảo thư mục logs tồn tại
        $logDirectory = [System.IO.Path]::GetDirectoryName($logFile)
        if (-not (Test-Path $logDirectory)) {
            New-Item -Path $logDirectory -ItemType Directory -Force
        }

        # Ghi vào file log
        Add-Content -Path $logFile -Value $logMessage
    }
}

# Function to check if an IP address exists in phpIPAM
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
        $request.ProtocolVersion = [System.Net.HttpVersion]::Version11
        $request.Timeout = 5000  # Timeout in milliseconds (5 seconds)

        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $result = $reader.ReadToEnd()

        $parsedJson = $result | ConvertFrom-Json

        if ($parsedJson.data) {
            Write-Log "IP $ipAddress found in phpIPAM." $logToFile
            return $parsedJson.data  # Return IP address details
        } else {
            Write-Log "IP $ipAddress not found in phpIPAM." $logToFile
            return $null
        }
    } catch [System.Net.WebException] {
        # Handle 404 errors (IP not found in phpIPAM)
        if ($_.Response -and $_.Response.StatusCode -eq 404) {
            Write-Log "IP $ipAddress not found in phpIPAM. Proceeding to add it." $logToFile
        } else {
            # Handle other errors
            Write-Log "Error checking IP $ipAddress in phpIPAM: $_" $logToFile
        }
        return $null
    }
}

# Function to retrieve all subnets from phpIPAM
function Get-AllSubnetsFromPhpIPAM {
    param (
        [bool]$logToFile = $false
    )

    Write-Log "Retrieving all subnets from phpIPAM..." $logToFile

    $getSubnetsUrl = "$apiBase/sections/$sectionId/subnets/"
    try {
        $request = [System.Net.HttpWebRequest]::Create($getSubnetsUrl)
        $request.Method = "GET"
        $request.Headers.Add("token", $token)
        $request.ContentType = "application/json"
        $request.ProtocolVersion = [System.Net.HttpVersion]::Version11

        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $result = $reader.ReadToEnd()

        # Manually parse JSON to handle duplicate keys
        $parsedJson = Parse-JsonHandlingDuplicates $result

        # Log all retrieved subnets for debugging purposes
        foreach ($subnet in $parsedJson.data) {
            Write-Log "Retrieved Subnet: $($subnet.subnet)/$($subnet.mask), Subnet ID: $($subnet.id)" $logToFile
        }

        Write-Log "Successfully retrieved all subnets from phpIPAM." $logToFile
        return $parsedJson.data
    } catch {
        Write-Log "Error retrieving subnets from phpIPAM: $_" $logToFile
        return $null
    }
}

# Function to parse JSON with duplicate key handling
function Parse-JsonHandlingDuplicates {
    param (
        [string]$jsonString
    )

    try {
        # Handle the "Used" and "used" issue manually
        $jsonString = $jsonString -replace '"Used":', '"UsedDuplicate":'  # Rename the duplicated key

        # Safely convert the JSON
        $jsonData = $jsonString | ConvertFrom-Json
        return $jsonData
    } catch {
        Write-Log "Error parsing JSON: $_"
        return $null
    }
}

# Function to add IP address to phpIPAM using the correct JSON payload format
function Add-IPToPhpIPAM {
    param (
        [string]$ipAddress,
        [string]$hostname,
        [string]$macAddress,
        [int]$subnetId,
        [bool]$logToFile = $false
    )

    # Convert MAC address to colon-separated format (phpIPAM typically uses this format)
    $macAddress = $macAddress -replace '-', ':'

    Write-Log "Adding IP $ipAddress to subnet $subnetId in phpIPAM..." $logToFile
    try {
        $ipData = @{
            "ip" = $ipAddress
            "subnetId" = $subnetId
            "hostname" = $hostname
            "mac" = $macAddress
            "description" = "$descriptionPrefix - $hostname"  # Use the description prefix from the variable
        }

        Write-Log "Payload to be sent: $(ConvertTo-Json $ipData -Depth 3)" $logToFile

        $addIpUrl = "$apiBase/addresses/"
        $request = [System.Net.HttpWebRequest]::Create($addIpUrl)
        $request.Method = "POST"
        $request.Headers.Add("token", $token)
        $request.ContentType = "application/json"
        $request.ProtocolVersion = [System.Net.HttpVersion]::Version11

        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($ipData | ConvertTo-Json))
        $request.ContentLength = $bytes.Length
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bytes, 0, $bytes.Length)
        $requestStream.Close()

        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $result = $reader.ReadToEnd()

        Write-Log "Successfully added IP $ipAddress to phpIPAM." $logToFile
        return $result
    } catch {
        Write-Log "Error adding IP $ipAddress to phpIPAM: $_" $logToFile
        if ($_.Exception.Response) {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorResult = $reader.ReadToEnd()
            Write-Log "Det
