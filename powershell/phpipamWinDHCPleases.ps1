# -----------------------------
# Tuyên bố miễn trừ trách nhiệm pháp lý:
# -----------------------------
# Script này được cung cấp "nguyên trạng" mà không có bất kỳ bảo đảm rõ ràng hay ngầm định nào, bao gồm nhưng không giới hạn các bảo đảm ngầm định về tính thương mại và sự phù hợp cho một mục đích cụ thể.
# Tác giả script không chịu trách nhiệm về bất kỳ thiệt hại hoặc mất mát dữ liệu nào gây ra bởi việc sử dụng script này, trực tiếp hay gián tiếp.
# Người dùng có trách nhiệm xem xét kỹ lưỡng, kiểm thử và chỉnh sửa script trước khi triển khai trong môi trường sản xuất.
# Script này chỉ nhằm mục đích giáo dục và thông tin. Sử dụng hoàn toàn theo rủi ro và quyết định của riêng bạn.
# -----------------------------
# Mục đích của Script:
# -----------------------------
# Mục đích chính của script là đồng bộ các lease DHCP từ máy chủ DHCP Windows với hệ thống quản lý IP phpIPAM (IP Address Management).
# Script sẽ lấy tất cả các lease DHCP từ máy chủ DHCP Windows và cập nhật vào phpIPAM, đảm bảo cơ sở dữ liệu phpIPAM phản ánh chính xác trạng thái hiện tại của máy chủ DHCP.
# Tùy chọn cập nhật các trường tùy chỉnh (custom fields) trong phpIPAM, chẳng hạn như thời hạn lease hoặc trạng thái thiết bị. Hãy đảm bảo các trường tùy chỉnh cần thiết đã được định nghĩa trong phpIPAM để hoạt động đúng.
# Tóm tắt chức năng:
# 1. Lấy tất cả các lease DHCP trong các scope từ máy chủ DHCP Windows.
# 2. Cập nhật thông tin IP vào phpIPAM.
# - Script có thể được chạy thủ công hoặc lên lịch tự động thông qua Windows Task Scheduler
# trên chính máy chủ DHCP hoặc một máy khác có kết nối mạng tới máy chủ DHCP.
# 3. Tùy chọn ghi log tất cả các hoạt động vào file để phục vụ kiểm toán và khắc phục sự cố.
# 4. Tùy chọn thực hiện kiểm tra host (ping) trước khi thêm IP vào phpIPAM.
# -----------------------------
# Hướng dẫn cấu hình:
# -----------------------------
# Các yêu cầu bắt buộc để script hoạt động:
# 1. URL cơ sở của phpIPAM API, Section ID và API Token.
# 2. Script PowerShell cần được chạy trên máy có quyền truy cập vào máy chủ DHCP Windows và yêu cầu quyền Administrator.
# 3. Cấu hình Timeout: Script áp dụng timeout 5 giây cho các yêu cầu API phpIPAM. Nếu không nhận được phản hồi trong thời gian này, yêu cầu sẽ được coi là thất bại, script sẽ ghi log lỗi và tiếp tục.
# - Phần này nằm trong "Function to check if an IP address exists in phpIPAM"
# 4. Cấu hình Logging: Script hỗ trợ ghi log vào file để kiểm toán và khắc phục sự cố. Đặt $logToFile = $true để bật ghi log vào file. Lưu ý rằng
# việc bật logging có thể ảnh hưởng đến hiệu suất, đặc biệt khi xử lý số lượng lease lớn. Nên tắt logging trong môi trường sản xuất để đạt hiệu suất tối ưu.
# Chạy dưới dạng Scheduled Task:
# ----------------------------
# Bạn có thể thiết lập script chạy tự động bằng cách thêm nó vào Windows Task Scheduler.
# 1. Mở Task Scheduler.
# 2. Tạo một task mới.
# 3. Đặt trigger để chạy task theo khoảng thời gian mong muốn (ví dụ: hàng giờ, hàng ngày).
# 4. Đặt action là "Start a program" và trỏ tới powershell.exe.
# 5. Trong phần arguments, cung cấp đường dẫn tới script (ví dụ: `-File C:\path\to\script.ps1`).
# 6. Đảm bảo task được chạy dưới tài khoản có đủ quyền truy cập cả máy chủ DHCP và phpIPAM.
# -----------------------------
# Định nghĩa URL cơ sở API phpIPAM, section ID và token API
# -----------------------------
$apiBase = "https://yourservernameorip/api/appcode"
$token = "yourtokengoeshere"
$sectionId = YourSection#
# Các tính năng tùy chọn
$descriptionPrefix = "Imported from WIN DHCP" # Đặt tiền tố mô tả cho các mục IP và subnet trong phpIPAM.
$useFullHostname = $false # Đặt $false để chỉ sử dụng phần hostname trước dấu chấm đầu tiên
$checkHost = $false # Kiểm tra host (Ping): Script có tính năng tùy chọn ping kiểm tra trước khi thêm IP vào phpIPAM.
                        # Bật tính năng này ($checkHost = $true) sẽ kiểm tra xem IP có thể truy cập được không trước khi tiếp tục. Lưu ý rằng
                        # việc bật tùy chọn này có thể làm tăng đáng kể thời gian xử lý tổng thể, đặc biệt với số lượng lease lớn,
                        # vì mỗi IP sẽ được ping riêng lẻ.
# Cấu hình logging
$logToFile = $false # Bật hoặc tắt ghi log vào file (đặt $true để bật)
# Bỏ qua xác thực chứng chỉ SSL (chỉ sử dụng khi cần thiết với chứng chỉ tự ký)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
# Buộc sử dụng TLS 1.2 để giao tiếp an toàn với API phpIPAM.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# -----------------------------
# Hàm ghi log: Ghi ra console và tùy chọn ghi vào file log, bổ sung logging
# Lưu ý quan trọng về Logging: Việc bật ghi log vào file ($logToFile = $true) có thể làm tăng đáng kể I/O đĩa, đặc biệt khi
# script xử lý nhiều lease DHCP. Khuyến nghị chỉ bật logging để debug hoặc kiểm toán, và tắt trong môi trường sản xuất
# để cải thiện hiệu suất.
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
# Hàm kiểm tra xem một địa chỉ IP có tồn tại trong phpIPAM hay không
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
        $request.Timeout = 5000 # Timeout in milliseconds (5 seconds)
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $result = $reader.ReadToEnd()
        $parsedJson = $result | ConvertFrom-Json
        if ($parsedJson.data) {
            Write-Log "IP $ipAddress found in phpIPAM." $logToFile
            return $parsedJson.data # Return IP address details
        } else {
            Write-Log "IP $ipAddress not found in phpIPAM." $logToFile
            return $null
        }
    } catch [System.Net.WebException] {
        # Xử lý lỗi 404 (IP không tồn tại trong phpIPAM)
        if ($_.Response -and $_.Response.StatusCode -eq 404) {
            Write-Log "IP $ipAddress not found in phpIPAM. Proceeding to add it." $logToFile
        } else {
            # Xử lý các lỗi khác
            Write-Log "Error checking IP $ipAddress in phpIPAM: $_" $logToFile
        }
        return $null
    }
}
# Hàm lấy tất cả các subnet từ phpIPAM
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
        # Phân tích JSON thủ công để xử lý các key trùng lặp
        $parsedJson = Parse-JsonHandlingDuplicates $result
        # Ghi log tất cả subnet lấy được để debug
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
# Hàm phân tích JSON có xử lý key trùng lặp
function Parse-JsonHandlingDuplicates {
    param (
        [string]$jsonString
    )
    try {
        # Xử lý thủ công vấn đề "Used" và "used"
        $jsonString = $jsonString -replace '"Used":', '"UsedDuplicate":' # Đổi tên key trùng
        # Chuyển đổi JSON an toàn
        $jsonData = $jsonString | ConvertFrom-Json
        return $jsonData
    } catch {
        Write-Log "Error parsing JSON: $_"
        return $null
    }
}
# Hàm thêm địa chỉ IP vào phpIPAM với định dạng payload JSON đúng
function Add-IPToPhpIPAM {
    param (
        [string]$ipAddress,
        [string]$hostname,
        [string]$macAddress,
        [int]$subnetId,
        [bool]$logToFile = $false
    )
    # Chuyển MAC address sang định dạng phân cách bằng dấu hai chấm (phpIPAM thường dùng định dạng này)
    $macAddress = $macAddress -replace '-', ':'
    Write-Log "Adding IP $ipAddress to subnet $subnetId in phpIPAM..." $logToFile
    try {
        $ipData = @{
            "ip" = $ipAddress
            "subnetId" = $subnetId
            "hostname" = $hostname
            "mac" = $macAddress
            "description" = "$descriptionPrefix - $hostname" # Sử dụng tiền tố mô tả từ biến
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
            Write-Log "Detailed response: $errorResult" $logToFile
        }
    }
}
# Hàm tính toán dải (IP bắt đầu và kết thúc) của một subnet
function Get-SubnetRange {
    param (
        [string]$subnetAddress,
        [int]$mask
    )
    # Đảm bảo địa chỉ subnet hợp lệ
    if ([string]::IsNullOrEmpty($subnetAddress)) {
        Write-Log "Subnet address is null or empty. Skipping subnet."
        return $null
    }
    try {
        Write-Log "Calculating range for subnet $subnetAddress/$mask"
        # Chuyển địa chỉ subnet sang mảng byte IP
        $subnetIpBytes = [System.Net.IPAddress]::Parse($subnetAddress).GetAddressBytes()
        [Array]::Reverse($subnetIpBytes) # Đảm bảo thứ tự byte đúng
        $subnetIpInt = [BitConverter]::ToUInt32($subnetIpBytes, 0)
        # Tính số bit host (số IP khả dụng trong subnet)
        $hostBits = 32 - $mask
        $hostCount = [Math]::Pow(2, $hostBits) - 1
        # Tính IP khả dụng đầu tiên và cuối cùng
        $startIpInt = $subnetIpInt + 1
        $endIpInt = $subnetIpInt + $hostCount - 1
        # Chuyển ngược lại thành địa chỉ IP
        $startIpBytes = [BitConverter]::GetBytes([uint32]$startIpInt)
        [Array]::Reverse($startIpBytes)
        $startIp = [System.Net.IPAddress]::new($startIpBytes)
        $endIpBytes = [BitConverter]::GetBytes([uint32]$endIpInt)
        [Array]::Reverse($endIpBytes)
        $endIp = [System.Net.IPAddress]::new($endIpBytes)
        Write-Log "Calculated range for Subnet ${subnetAddress}/${mask}: Start IP: ${startIp}, End IP: ${endIp}"
        return @{
            "StartIp" = $startIp.ToString()
            "EndIp" = $endIp.ToString()
        }
    } catch {
        Write-Log "Error calculating range for Subnet ${subnetAddress}/${mask}: $_"
        return $null
    }
}
# Hàm khớp một địa chỉ IP với subnet bằng cách kiểm tra xem nó có nằm trong dải hay không
function Match-SubnetForIP {
    param (
        [string]$ipAddress,
        [array]$subnets, # Danh sách tất cả subnet từ phpIPAM
        [bool]$logToFile = $false
    )
    Write-Log "Attempting to match IP $ipAddress to a subnet..." $logToFile
    foreach ($subnet in $subnets) {
        $subnetAddress = [System.Net.IPAddress]::Parse($subnet.subnet).IPAddressToString()
        $mask = $subnet.mask
        # Tính dải của subnet
        $subnetRange = Get-SubnetRange -subnetAddress $subnetAddress -mask $mask
        # Ghi log dải subnet để debug
        Write-Log "Subnet: $subnetAddress/$mask, Start: $($subnetRange.StartIp), End: $($subnetRange.EndIp), Subnet ID: $($subnet.id)" $logToFile
        # Kiểm tra xem IP có nằm trong dải của subnet này không
        if (Is-IPInRange -ipAddress $ipAddress -subnetStart $subnetRange.StartIp -subnetEnd $subnetRange.EndIp) {
            Write-Log "Matched IP $ipAddress to subnet ID $($subnet.id)" $logToFile
            return $subnet.id
        }
    }
    Write-Log "No matching subnet found for IP $ipAddress in phpIPAM." $logToFile
    return $null
}
# Hàm kiểm tra xem một IP có nằm trong dải subnet đã cho không
function Is-IPInRange {
    param (
        [string]$ipAddress,
        [string]$subnetStart,
        [string]$subnetEnd
    )
    # Chuyển IP, start và end sang số nguyên để so sánh
    $ipBytes = [System.Net.IPAddress]::Parse($ipAddress).GetAddressBytes()
    [Array]::Reverse($ipBytes)
    $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
    $startIpBytes = [System.Net.IPAddress]::Parse($subnetStart).GetAddressBytes()
    [Array]::Reverse($startIpBytes)
    $startIpInt = [BitConverter]::ToUInt32($startIpBytes, 0)
    $endIpBytes = [System.Net.IPAddress]::Parse($subnetEnd).GetAddressBytes()
    [Array]::Reverse($endIpBytes)
    $endIpInt = [BitConverter]::ToUInt32($endIpBytes, 0)
    Write-Log "Comparing IP: $ipAddress with Start: $subnetStart and End: $subnetEnd"
    if ($ipInt -ge $startIpInt -and $ipInt -le $endIpInt) {
        Write-Log "IP $ipAddress falls within the range $subnetStart to $subnetEnd"
        return $true
    } else {
        Write-Log "IP $ipAddress is outside the range $subnetStart to $subnetEnd"
        return $false
    }
}
# Hàm xóa một địa chỉ IP khỏi phpIPAM
function Remove-IPFromPhpIPAM {
    param (
        [string]$ipId, # Sử dụng ID của bản ghi IP thay vì địa chỉ IP để xóa
        [bool]$logToFile = $false
    )
    Write-Log "Deleting IP entry with ID $ipId from phpIPAM..." $logToFile
    $deleteIpUrl = "$apiBase/addresses/$ipId/"
    try {
        $request = [System.Net.HttpWebRequest]::Create($deleteIpUrl)
        $request.Method = "DELETE"
        $request.Headers.Add("token", $token)
        $request.ContentType = "application/json"
        $request.ProtocolVersion = [System.Net.HttpVersion]::Version11
        $response = $request.GetResponse()
        Write-Log "Successfully deleted IP entry with ID $ipId from phpIPAM." $logToFile
    } catch {
        Write-Log "Error deleting IP entry with ID $ipId from phpIPAM: $_" $logToFile
    }
}
# Hàm xử lý các lease DHCP và tìm subnet phù hợp trong phpIPAM
function Process-DhcpLeases {
    param (
        [bool]$logToFile = $false
    )
    # Lấy tất cả subnet từ phpIPAM
    $subnets = Get-AllSubnetsFromPhpIPAM -logToFile $logToFile
    if (-not $subnets) {
        Write-Log "No subnets retrieved from phpIPAM. Exiting..." $logToFile
        return
    }
    # Lấy tất cả các scope DHCP
    $scopes = Get-DhcpServerv4Scope
    foreach ($scope in $scopes) {
        $scopeId = $scope.ScopeId.IPAddressToString
        Write-Log "Processing leases for scope: $scopeId" $logToFile
        # Lấy tất cả lease của scope hiện tại
        $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId
        foreach ($lease in $leases) {
            $ipAddress = $lease.IPAddress.IPAddressToString
            # Quyết định sử dụng hostname đầy đủ hay chỉ phần đầu
            $hostname = if ($useFullHostname) {
                $lease.HostName # Hostname đầy đủ
            } else {
                ($lease.HostName -split '\.')[0] # Hostname rút gọn (phần trước dấu chấm đầu tiên)
            }
            $macAddress = $lease.ClientId -replace '-', ':' # Chuyển MAC sang định dạng phân cách bằng dấu hai chấm
            $state = $lease.AddressState # Có thể là Active, Expired, v.v.
            Write-Log "Processing Lease: IP: $ipAddress, Hostname: $hostname, MAC: $macAddress, State: $state" $logToFile
            # Chỉ xử lý các lease đang active
            if ($state -ne 'Active') {
                Write-Log "Skipping IP $ipAddress because it is not active." $logToFile
                continue
            }
            # Tùy chọn thực hiện ping (kiểm tra host) trước khi tiếp tục
            if ($checkHost) {
                Write-Log "Pinging IP $ipAddress to check if it's alive..." $logToFile
                $pingResult = Test-Connection -ComputerName $ipAddress -Count 1 -Quiet
                if (-not $pingResult) {
                    Write-Log "IP $ipAddress is not responding to ping. Skipping." $logToFile
                    continue
                } else {
                    Write-Log "IP $ipAddress responded to ping." $logToFile
                }
            }
            # Tìm subnet ID phù hợp trong phpIPAM cho lease này
            $matchingSubnet = $null
            foreach ($subnet in $subnets) {
                $subnetRange = Get-SubnetRange -subnetAddress $subnet.subnet -mask $subnet.mask
                if (Is-IPInRange -ipAddress $ipAddress -subnetStart $subnetRange.StartIp -subnetEnd $subnetRange.EndIp) {
                    $matchingSubnet = $subnet
                    Write-Log "Matched IP $ipAddress to subnet ID $($subnet.id)" $logToFile
                    break
                }
            }
            if (-not $matchingSubnet) {
                Write-Log "No matching subnet found for IP $ipAddress in phpIPAM. Skipping." $logToFile
                continue
            }
            # Kiểm tra xem IP đã tồn tại trong phpIPAM chưa
            $existingIpDetails = Get-IPAddressFromPhpIPAM -ipAddress $ipAddress -logToFile $logToFile
            if ($existingIpDetails) {
                # Chuẩn hóa MAC address từ phpIPAM sang định dạng dấu hai chấm
                $oldMacAddress = $existingIpDetails.mac -replace '-', ':'
                # So sánh MAC address
                if ($oldMacAddress -ne $macAddress) {
                    Write-Log "MAC address mismatch for IP $ipAddress. Old MAC: $oldMacAddress, New MAC: $macAddress" $logToFile
                    # Xóa bản ghi cũ
                    Remove-IPFromPhpIPAM -ipId $existingIpDetails.id -logToFile $logToFile
                } else {
                    Write-Log "IP $ipAddress with matching MAC address already exists in phpIPAM. Skipping addition." $logToFile
                    continue
                }
            } else {
                Write-Log "phpIPAM response: IP $ipAddress does not exist. Proceeding to add it." $logToFile
            }
            # Thêm IP vào phpIPAM với subnet ID đúng
            Add-IPToPhpIPAM -ipAddress $ipAddress -hostname $hostname -macAddress $macAddress -subnetId $matchingSubnet.id -logToFile $logToFile
        }
    }
}
# Điểm vào chính
Process-DhcpLeases -logToFile $logToFile
