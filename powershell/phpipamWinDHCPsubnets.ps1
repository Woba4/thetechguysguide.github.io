# -----------------------------
# Tuyên bố miễn trừ trách nhiệm pháp lý:
# -----------------------------
# Script này được cung cấp "nguyên trạng" và không có bất kỳ đảm bảo nào, 
# bao gồm nhưng không giới hạn, các đảm bảo ngụ ý về khả năng thương mại 
# hoặc phù hợp với một mục đích cụ thể.
# Tác giả của script này không chịu trách nhiệm với bất kỳ thiệt hại hoặc mất mát dữ liệu nào 
# gây ra bởi việc sử dụng script này, trực tiếp hoặc gián tiếp.
# Người dùng có trách nhiệm tự xem xét kỹ lưỡng, kiểm tra, và sửa đổi script này 
# trước khi triển khai trong môi trường sản xuất.
# Script này chỉ nhằm mục đích giáo dục và cung cấp thông tin. 
# Sử dụng script này là hoàn toàn tự chịu rủi ro và cân nhắc cá nhân.
# Hãy kiểm tra kỹ lưỡng trong môi trường không phải production.

# -----------------------------
# Mục đích của Script này:
# -----------------------------
# Mục đích chính của script là tích hợp các scope và lease của DHCP server Windows 
# với hệ thống quản lý địa chỉ IP phpIPAM.
# Script sẽ lấy tất cả DHCP scopes và leases từ Windows DHCP server 
# và sau đó cập nhật phpIPAM với thông tin subnet, đảm bảo rằng cơ sở dữ liệu phpIPAM 
# phản ánh đúng trạng thái hiện tại của DHCP server.
# Script cũng có thể tùy chọn cập nhật các trường tùy chỉnh 
# cho thời gian lease (`custom_leaseDuration`) và trạng thái subnet (`custom_subnetState`), 
# cho phép người dùng phpIPAM theo dõi thông tin lease và subnet từ DHCP.
# Lưu ý: Các lease sẽ được xử lý trong bản phát hành thứ hai.

# Tóm tắt chức năng:
# 1. Lấy tất cả DHCP scopes từ Windows DHCP server.
# 2. Cập nhật phpIPAM với thông tin subnet (VD mô tả, thời gian lease, trạng thái subnet).
#    - Script có thể chạy thủ công hoặc chạy tự động bằng Windows Task Scheduler
#      trên chính DHCP server hoặc một máy khác có quyền truy cập vào DHCP server 
#      (bạn phải cài RSAT và có quyền admin trên server).
# 3. Tùy chọn ghi log cho toàn bộ hoạt động để phục vụ audit và xử lý lỗi.
# 4. Hỗ trợ các trường tùy chỉnh trong phpIPAM để lưu thời gian lease và trạng thái subnet.
# 5. Tùy chọn kiểm tra host (ping) trước khi thêm IP vào phpIPAM.

# -----------------------------
# Hướng dẫn cấu hình:
# -----------------------------
# Các yêu cầu bắt buộc để script hoạt động:
# 1. Địa chỉ API base URL của phpIPAM, ID của Section, và API Token.
# 2. Script PowerShell phải được chạy trên máy có quyền truy cập vào DHCP server Windows 
#    và script phải chạy với quyền Administrator.
# 3. Đảm bảo phpIPAM đã có các custom fields sau (nếu dùng):
#    - `custom_leaseDuration`: Dùng để lưu thời gian lease của DHCP (tùy chọn).
#    - `custom_subnetState`: Lưu trạng thái subnet ("active" hoặc "inactive") (tùy chọn).
#    - `pingSubnet`: Kiểm soát việc subnet có được scan trạng thái hay không (mặc định: 0/tắt).
#    - `scanAgent`: Gán scan agent để quét subnet (mặc định: 1).
# 4. PowerShell 5.1 — script này được viết cho phiên bản này, chưa test trên PowerShell 7.x.

# Các tùy chọn:
# 1. `$useLeaseDuration`: đặt `$true` nếu muốn cập nhật trường lease duration vào phpIPAM.
# 2. `$useSubnetState`: đặt `$true` nếu muốn cập nhật trạng thái subnet.
# 3. `$checkHost`: đặt `$true` nếu muốn ping host trước khi thêm IP vào phpIPAM.
# 4. `$logToFileSubnet`: đặt `$true` để ghi log quá trình xử lý subnet vào file.
# 5. `$logToFileLeases`: đặt `$true` để ghi log quá trình xử lý lease.
# 6. `$descriptionPrefix`: đặt tiền tố cho mô tả khi thêm IP vào phpIPAM.

# Chạy như Scheduled Task:
# ----------------------------
# Bạn có thể thiết lập script chạy tự động bằng Task Scheduler.
# 1. Mở Task Scheduler.
# 2. Tạo task mới.
# 3. Chọn trigger theo thời gian mong muốn (VD chạy mỗi giờ, mỗi ngày,...).
# 4. Trong Action → chọn "Start a program" và trỏ tới PowerShell (`powershell.exe`).
# 5. Trong Arguments, thêm đường dẫn file script (VD `-File C:\path\script.ps1`).
# 6. Đảm bảo task chạy dưới tài khoản có quyền truy cập DHCP server và phpIPAM.

# -----------------------------
# Khai báo URL API, Section ID, Token của phpIPAM
# -----------------------------
$apiBase = "https://yourserverIPorNAME/api/APPID"
$token = "APP code goes here"
$sectionId = Numeric Value of the section example (3)

# Tùy chọn bật tắt các tính năng
$useLeaseDuration = $false
$useSubnetState = $false
$descriptionPrefix = "Imported from WIN DHCP"

# Giá trị mặc định
$scanAgent = 1
$pingSubnet = 1

# Custom fields
$leaseDurationField = "leaseDuration"
$subnetStateField = "subnetState"

# Vô hiệu hóa kiểm tra chứng chỉ SSL (nếu phpIPAM dùng SSL tự ký)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Bắt buộc dùng TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# -----------------------------
# Hàm ghi log
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
# Hàm chuyển subnet mask sang CIDR
# -----------------------------
function Convert-MaskToCIDR {
    param ([string]$mask)

    $octets = $mask.Split('.')
    $cidr = 0

    foreach ($octet in $octets) {
        $binaryOctet = [Convert]::ToString([int]$octet, 2)
        $cidr += ($binaryOctet -split '1').Length - 1
    }
    return $cidr
}

# -----------------------------
# Log lỗi API
# -----------------------------
function Log-ApiError {
    param (
        [System.Management.Automation.ErrorRecord]$exception,
        [bool]$logToFile = $false
    )

    $errorMessage = "Exception: $($exception.Exception.Message)"
    Write-Log $errorMessage $logToFile

    if ($exception.Exception -is [System.Net.WebException]) {
        $webException = $exception.Exception
        if ($webException.Response) {
            $errorStream = $webException.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorStream)
            $errorResult = $reader.ReadToEnd()
            Write-Log "Detailed error response: $errorResult" $logToFile
        }
    } else {
        Write-Log "No detailed web exception response available." $logToFile
    }
}

# -----------------------------
# Hàm tạo subnet trong phpIPAM
# -----------------------------
function Create-SubnetInPhpIPAM {
    param (
        [string]$subnet,
        [int]$mask,
        [string]$leaseDuration = $null,
        [string]$subnetState = $null,
        [string]$name,
        [bool]$logToFile = $false
    )

    Write-Log "Creating subnet with description: '$name'" $logToFile

    $subnetData = @{
        "subnet" = $subnet
        "mask" = $mask
        "sectionId" = $sectionId
        "description" = $name
        "scanAgent" = $scanAgent
        "pingSubnet" = $pingSubnet
    }

    if ($useLeaseDuration -and $leaseDuration) {
        $subnetData["custom_$leaseDurationField"] = $leaseDuration
    }

    if ($useSubnetState -and $subnetState) {
        $subnetData["custom_$subnetStateField"] = $subnetState
    }

    $createSubnetUrl = "$apiBase/subnets/"

    try {

        $request = [System.Net.HttpWebRequest]::Create($createSubnetUrl)
        $request.Method = "POST"
        $request.Headers.Add("token", $token)
        $request.ContentType = "application/json"

        $jsonData = $subnetData | ConvertTo-Json
        Write-Log "Sending POST request to create subnet with data: $jsonData" $logToFile

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonData)
        $request.ContentLength = $bytes.Length
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bytes, 0, $bytes.Length)
        $requestStream.Close()

        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $result = $reader.ReadToEnd()

        Write-Log "Successfully created subnet ${subnet}/${mask} in phpIPAM." $logToFile
        return $result
    } catch [System.Net.WebException] {
        Write-Log "Error creating subnet ${subnet}/${mask}." $logToFile
        Log-ApiError $_ $logToFile
    }
}

# -----------------------------
# Hàm cập nhật subnet trong phpIPAM
# -----------------------------
function Update-SubnetInPhpIPAM {
    param (
        [int]$subnetId,
        [string]$name,
        [string]$leaseDuration = $null,
        [string]$subnetState = $null,
        [bool]$logToFile = $false
    )

    Write-Log "Updating subnet with description: '$name'" $logToFile

    $updateData = @{
        "description" = $name
        "scanAgent" = $scanAgent
        "pingSubnet" = $pingSubnet
    }

    if ($useLeaseDuration -and $leaseDuration) {
        $updateData["custom_$leaseDurationField"] = $leaseDuration
    }

    if ($useSubnetState -and $subnetState) {
        $updateData["custom_$subnetStateField"] = $subnetState
    }

    $updateSubnetUrl = "$apiBase/subnets/$subnetId/"

    try {

        $request = [System.Net.HttpWebRequest]::Create($updateSubnetUrl)
        $request.Method = "PATCH"
        $request.Headers.Add("token", $token)
        $request.ContentType = "application/json"

        $jsonData = $updateData | ConvertTo-Json
        Write-Log "Sending PATCH request to update subnet with data: $jsonData" $logToFile

        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonData)
        $request.ContentLength = $bytes.Length
        $requestStream = $request.GetRequestStream()
        $requestStream.Write($bytes, 0, $bytes.Length)
        $requestStream.Close()

        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $result = $reader.ReadToEnd()

        Write-Log "Successfully updated subnet ID $subnetId." $logToFile
        return $result
    } catch [System.Net.WebException] {
        Write-Log "Error updating subnet ID ${subnetId}." $logToFile
        Log-ApiError $_ $logToFile
    }
}

# -----------------------------
# Hàm kiểm tra subnet đã tồn tại trong phpIPAM chưa
# -----------------------------
function Check-SubnetInPhpIPAM {
    param (
        [string]$subnet,
        [int]$mask,
        [bool]$logToFile = $false
    )

    $searchUrl = "$apiBase/subnets/search/$subnet/$mask"
    try {

        $request = [System.Net.HttpWebRequest]::Create($searchUrl)
        $request.Method = "GET"
        $request.Headers.Add("token", $token)
        $request.ContentType = "application/json"

        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $result = $reader.ReadToEnd()

        $jsonResult = $result | ConvertFrom-Json
        Write-Log "Subnet ${subnet}/${mask} already exists in phpIPAM." $logToFile
        return $jsonResult.data
    }
    catch [System.Net.WebException] {
        Log-ApiError $_ $logToFile
        return $null
    }
}

# -----------------------------
# Hàm xử lý các DHCP Scopes
# -----------------------------
function Process-DhcpScopes {
    param ([bool]$logToFile = $false)

    $scopes = Get-DhcpServerv4Scope

    foreach ($scope in $scopes) {

        $subnet = $scope.ScopeId.IPAddressToString
        $mask = Convert-MaskToCIDR -mask $scope.SubnetMask.IPAddressToString
        $name = $scope.Name.Trim()
        Write-Log "Retrieved scope: Subnet $subnet, Mask $mask, Name '$name'" $logToFile

        $leaseDuration = $scope.LeaseDuration
        $subnetState = if ($scope.State -eq 'Active') { "active" } else { "inactive" }

        Write-Log "Processing subnet $subnet with mask $mask and name '$name'" $logToFile

        $existingSubnet = Check-SubnetInPhpIPAM -subnet $subnet -mask $mask -logToFile $logToFile

        if (-not $existingSubnet) {
            Write-Log "phpIPAM reports that subnet $subnet/$mask does not exist. Attempting to create it." $logToFile
            Create-SubnetInPhpIPAM -subnet $subnet -mask $mask -leaseDuration $leaseDuration -subnetState $subnetState -name $name -logToFile $logToFile
        } else {
            Write-Log "Subnet $subnet/$mask already exists in phpIPAM." $logToFile
            Update-SubnetInPhpIPAM -subnetId $existingSubnet.id -name $name -leaseDuration $leaseDuration -subnetState $subnetState -logToFile $logToFile
        }
    }
}

# -----------------------------
# Bắt đầu xử lý
# -----------------------------
$logToFile = $true
Process-DhcpScopes -logToFile $logToFile
