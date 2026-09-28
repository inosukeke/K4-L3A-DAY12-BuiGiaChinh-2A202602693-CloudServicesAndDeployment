# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder ("Câu trả lời của bạn") bằng câu trả lời — đã thay đủ 10 câu.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Bùi Gia Chính  Mã học viên: 2A202602693

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống: deploy lên Railway nhưng quên thêm biến `AGENT_API_KEY` trong tab Variables.
Nếu có mặc định `"changeme"`, container vẫn khởi động, `/health` vẫn 200, Railway báo deploy
thành công, nên mình không biết gì cả. Trong khi đó `/ask` đang được bảo vệ bằng một khóa ai
cũng đoán được (`changeme` nằm ngay trong repo công khai), người lạ gọi thoải mái và mình trả
tiền LLM. Vì không có mặc định, pydantic ném `ValidationError` ngay lúc `get_settings()`:
container crash, deploy đỏ, log ghi rõ thiếu field `agent_api_key`. Lỗi lộ ra ngay lúc deploy
thay vì lúc nhận hóa đơn.

Chú ý mình phát hiện khi thử thật: ban đầu `get_settings()` chỉ được gọi khi có request, nên
`docker run` không truyền key thì container vẫn `Up` và `/health` vẫn 200, tức chưa thật sự
fail fast. Mình thêm `get_settings()` vào `lifespan` lúc khởi động. Sau đó chạy lại thì
container `Exited (3)` sau 2 giây với log `agent_api_key  Field required` và
`Application startup failed`.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log thật từ container agent sau khi gọi `/ask`:

`{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T16:06:58.514202+00:00", "user_id": "sv01", "tokens_in": 43, "tokens_out": 47, "cost_usd": 3.465e-05}`

Hai việc làm được mà `print("đã trả lời xong")` không làm được:
1. Lọc và tổng hợp theo trường: ví dụ lọc `event=ask_completed AND user_id=sv01` rồi cộng
   `cost_usd` để biết một user tiêu bao nhiêu tiền trong ngày, hoặc tìm user gọi nhiều nhất.
2. Đặt cảnh báo và vẽ biểu đồ tự động: ví dụ alert khi tổng `tokens_in` mỗi phút vượt ngưỡng,
   hoặc khi xuất hiện `level=error`. Mỗi dòng là một JSON nên máy parse được, không cần regex
   đoán câu chữ. Có `timestamp` UTC nên ghép log của nhiều instance vẫn đúng thứ tự.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu, `python:3.11`) | 1.19 GB (~1190 MB) |
| Multi-stage (`python:3.11-slim`) | 209 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Hai số trên là mình đo bằng `docker images` (bản 1 stage build từ Dockerfile gốc của lab,
cùng `.dockerignore` đã sửa). Chênh khoảng 980 MB, gồm:
- Base image: `python:3.11` bản đầy đủ dựa trên Debian có sẵn gcc, make, header C, git,
  nhiều thư viện `-dev`... dùng để compile. Lúc chạy app không cần mấy thứ đó.
  `python:3.11-slim` bỏ hết, riêng phần này chiếm gần như toàn bộ chênh lệch.
- Stage builder: cache pip và các file tạm lúc cài chỉ nằm ở stage builder. Stage runtime chỉ
  `COPY --from=builder /opt/venv`, tức là chỉ lấy thư viện đã cài xong.
- Source: bản 1 stage `COPY . .` cả repo (tests, docs...); bản multi-stage chỉ copy `app/`
  và `utils/`.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Mình thử thật: đổi `SERVICE_VERSION` trong `app/main.py` rồi `docker build --progress=plain`.
Các bước `FROM`, `RUN python -m venv`, `COPY requirements.txt`, `RUN pip install`,
`RUN groupadd/useradd`, `COPY --from=builder /opt/venv` đều báo `CACHED`. Chỉ 2 layer cuối
chạy lại: `COPY app/ ./app/` (vì file trong app/ đổi) và `COPY utils/ ./utils/` (layer sau một
layer đã đổi thì cũng phải làm lại). Build lại mất vài giây.

Nếu đặt `COPY . .` lên trước `RUN pip install`: sửa bất kỳ file nào cũng làm checksum của
layer COPY đổi, nên cache của mọi layer phía sau bị bỏ. `pip install` sẽ tải và cài lại toàn
bộ fastapi, uvicorn, redis... mỗi lần sửa một ký tự, mất cả phút thay vì vài giây, tốn băng
thông và làm CI chậm.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện khi container chạy bằng root:
1. Code có lỗ hổng (ví dụ thư viện parse input bị RCE, hoặc mình lỡ gọi `subprocess` với
   input người dùng), kẻ tấn công chạy được lệnh trong container.
2. Process đó là uid 0. Root trong container có thể ghi đè mọi file của image, cài thêm công
   cụ, đọc mọi secret trong env/filesystem.
3. Nếu container được mount thứ nhạy cảm (`/var/run/docker.sock`, thư mục host), chạy
   `--privileged`, hoặc kernel có lỗ hổng escape, thì uid 0 trong container là uid 0 trên
   host. Kẻ tấn công thành root trên máy host và các container khác.

`USER app` (uid 10001) cắt chuỗi ở bước 2: shell chiếm được chỉ là user thường, không ghi được
vào thư mục hệ thống, không cài được gói, và khi thoát ra host thì là uid 10001 không có quyền
gì. Mình đã kiểm tra: `docker compose exec agent id` ra `uid=10001(app) gid=10001(app)`.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Tối đa 20 request trong khoảng 2 giây. Cách làm: gửi 10 request lúc 10:00:59 (vẫn trong
phút 10:00, còn quota), đồng hồ sang 10:01:00 thì bộ đếm reset về 0, gửi tiếp 10 request lúc
10:01:00–10:01:01. Cả 20 đều hợp lệ theo luật "10/phút đồng hồ", tức gấp đôi hạn mức trong
2 giây.

Với sliding window của mình, mỗi request nằm trong ZSET với score là timestamp. Lúc 10:01:01,
`ZREMRANGEBYSCORE` chỉ xóa những request cũ hơn 60 giây, nên 10 request lúc 10:00:59 vẫn còn
được đếm và request thứ 11 bị 429. Mình thấy đúng hành vi đó khi bắn 15 request liên tiếp
lên Railway: `200 ×10` rồi `429 ×5`.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

Rate limit đếm số lần gọi trong 60 giây gần nhất (chống spam, bảo vệ tài nguyên theo thời
gian ngắn). Cost guard đếm số tiền đã tiêu trong tháng (bảo vệ ngân sách theo thời gian dài).
Một cái đo tần suất, một cái đo tổng chi phí.

- Rate limit cho qua nhưng cost guard chặn: user gọi đều 5 request/phút (dưới hạn 10), mỗi
  request là prompt dài hàng chục nghìn token với history lớn. Không lần nào vi phạm rate
  limit, nhưng sau vài ngày tổng `cost:<user>:2026-09` vượt 10 USD nên bị 402.
- Rate limit chặn nhưng cost guard cho qua: một script lỗi bắn 50 request "hi" trong 5 giây.
  Mỗi request chỉ tốn khoảng 0.00002 USD nên ngân sách gần như chưa dùng, nhưng từ request
  thứ 11 đã bị 429.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Nếu `/health` cũng kiểm tra Redis và Redis mất kết nối 30 giây:
1. Giây 0: Redis mất kết nối. Cả 3 container cùng lúc trả 503 ở endpoint health.
2. Sau vài lần check fail liên tiếp (theo `retries`), orchestrator coi cả 3 container là
   unhealthy, nên kill và restart cả 3, dù process Python hoàn toàn bình thường.
3. Container mới khởi động xong mà Redis vẫn chưa về, health tiếp tục fail, restart tiếp:
   vòng lặp restart, thậm chí có backoff và kéo dài quá 30 giây.
4. Trong lúc restart, mọi request đang xử lý bị cắt, kể cả request không cần Redis. Cả dịch
   vụ sập hẳn thay vì chỉ giảm chức năng.
5. Redis về lại, nhưng container vẫn đang trong vòng restart và khởi động lại nên downtime dài
   hơn nhiều so với 30 giây gốc.

Khi tách riêng: `/health` vẫn 200 nên không ai bị restart, còn `/ready` trả 503 nên load
balancer chỉ tạm ngừng gửi traffic. Redis về thì `/ready` lại 200 và traffic quay lại ngay.
Mình đã thử `docker compose stop redis`: `/health` 200, `/ready` 503 `{"redis":false}`; bật
lại Redis thì `/ready` về 200.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Mình chạy 3 agent sau nginx
(`docker compose -f docker-compose.yml -f docker-compose.scale.yml --profile lb up -d --scale agent=3`)
và gọi 6 lần `/ask` với cùng `X-User-Id: sv-scale`. Log cho thấy mỗi replica nhận đúng 2
request (round-robin), vậy mà `history_length` tăng đều 0, 2, 4, 6, 8, 10 vì cả 3 cùng
đọc/ghi một list `history:sv-scale` trong Redis.

Nếu lưu trong dict Python, mỗi container có dict riêng. Với round-robin A, B, C, A, B, C, con
số sẽ là 0, 0, 0, 2, 2, 2: mỗi instance chỉ nhớ những lượt rơi vào chính nó, nên agent
"quên" câu trước mỗi khi request sang container khác. Container restart hoặc deploy bản mới
thì history về 0 hết. Mình cũng thấy điều ngược lại khi dùng Redis: sau khi tạo lại container
agent, user `sv01` vẫn còn `history_length` 4, rồi 6.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

Lỗi thật mình gặp: gọi thử `/ask` bằng `curl -d '{"question":"Docker là gì?"}'` trong Git
Bash trên Windows thì nhận `400 {"detail":"There was an error parsing the body"}`, trong khi
request thiếu key vẫn ra 401 và `{"question":"test"}` thì 200. Cách tìm: lỗi chỉ xảy ra với câu
có dấu tiếng Việt, và thông báo là parse body chứ không phải validation, nên mình nghi byte gửi
đi không phải UTF-8. Gửi cùng câu hỏi bằng `httpx` của Python (json UTF-8) thì 200 bình thường.
Vậy app không lỗi, lỗi ở encoding của terminal Windows (codepage không phải UTF-8). Cách sửa
khi test: dùng client gửi UTF-8 hoặc `--data-binary @file.json` lưu dạng UTF-8.

Một lỗi mình chặn trước khi deploy: `railway.toml` gốc có
`startCommand = "uvicorn ... --port $PORT"`. Với Dockerfile builder, start command của Railway
không chạy qua shell nên `$PORT` có thể không được thay giá trị và uvicorn không bind đúng
cổng, dẫn đến health check timeout. Mình bỏ `startCommand` để Railway dùng `CMD` trong
Dockerfile (`sh -c "exec uvicorn ... --port ${PORT:-8000}"`). Deploy đầu tiên SUCCESS,
`/health` 200 và `/ready` 200 `redis:true`.
