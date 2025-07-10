#!/bin/bash

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

# Danh sách node-id
node_ids=(
    12427239
    12455371
    12456035
    12456075
    12456602
    12484488
    12485317
    12485336
    12485503
    12485507
    12742229
)

# Tạo các cửa sổ screen
for i in "${!node_ids[@]}"; do
    screen_name="N$((i+1))"
    node_id="${node_ids[i]}"
    
    # Tạo cửa sổ screen mới với tên screen_name
    screen -dmS "$screen_name"
    
    # Gửi lệnh vào cửa sổ screen
    screen -S "$screen_name" -X stuff "nexus-network start --node-id $node_id\n"
    
    echo "Đã tạo cửa sổ screen $screen_name với node-id $node_id"
done

echo "Hoàn tất! Sử dụng 'screen -ls' để xem danh sách các cửa sổ screen."
