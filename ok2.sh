#!/bin/bash

# URL mặc định
DEFAULT_NODE_URL="https://raw.githubusercontent.com/lucduong2406/SCREEN/refs/heads/main/A1"

# Kiểm tra tham số URL
if [ -n "$1" ]; then
    NODE_URL="$1"
    echo "Sử dụng URL từ tham số: $NODE_URL"
else
    # Hỏi người dùng nhập URL
    read -p "Nhập URL chứa danh sách node-id (nhấn Enter để dùng mặc định: $DEFAULT_NODE_URL): " input_url
    if [ -z "$input_url" ]; then
        NODE_URL="$DEFAULT_NODE_URL"
        echo "Sử dụng URL mặc định: $NODE_URL"
    else
        NODE_URL="$input_url"
        echo "Sử dụng URL do người dùng cung cấp: $NODE_URL"
    fi
fi

# Kiểm tra và cài đặt screen nếu chưa có
if ! command -v screen &> /dev/null; then
    echo "Screen chưa được cài đặt. Đang cài đặt screen..."
    sudo apt update
    sudo apt install -y screen
    if [ $? -eq 0 ]; then
        echo "Cài đặt screen thành công."
    else
        echo "Lỗi khi cài đặt screen. Vui lòng kiểm tra."
        exit 1
    fi
else
    echo "Screen đã được cài đặt."
fi

# Kiểm tra và cài đặt curl nếu chưa có
if ! command -v curl &> /dev/null; then
    echo "Curl chưa được cài đặt. Đang cài đặt curl..."
    sudo apt update
    sudo apt install -y curl
    if [ $? -eq 0 ]; then
        echo "Cài đặt curl thành công."
    else
        echo "Lỗi khi cài đặt curl. Vui lòng kiểm tra."
        exit 1
    fi
else
    echo "Curl đã được cài đặt."
fi

# Tải danh sách node-id từ URL
echo "Đang tải danh sách node-id từ $NODE_URL..."
node_ids=$(curl -s "$NODE_URL")
if [ $? -ne 0 ]; then
    echo "Lỗi khi tải danh sách node-id từ $NODE_URL. Vui lòng kiểm tra URL hoặc kết nối mạng."
    exit 1
fi

# Chuyển đổi danh sách node-id thành mảng
IFS=$'\n' read -d '' -r -a node_array <<< "$node_ids"
if [ ${#node_array[@]} -eq 0 ]; then
    echo "Danh sách node-id rỗng. Vui lòng kiểm tra nội dung tại $NODE_URL."
    exit 1
fi

# Tạo các cửa sổ screen
for i in "${!node_array[@]}"; do
    screen_name="N$((i+1))"
    node_id="${node_array[i]}"
    
    # Kiểm tra node-id có hợp lệ không (không rỗng và là số)
    if [[ -z "$node_id" || ! "$node_id" =~ ^[0-9]+$ ]]; then
        echo "Bỏ qua node-id không hợp lệ: $node_id"
        continue
    fi
    
    # Tạo cửa sổ screen mới với tên screen_name
    screen -dmS "$screen_name"
    
    # Gửi lệnh vào cửa sổ screen
    screen -S "$screen_name" -X stuff "./nexus-network start --node-id $node_id\n"
    
    echo "Đã tạo cửa sổ screen $screen_name với node-id $node_id"
done

echo "Hoàn tất! Sử dụng 'screen -ls' để xem danh sách các cửa sổ screen."
