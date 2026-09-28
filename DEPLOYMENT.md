# Thông Tin Deploy — Checkpoint 5

> Điền file này sau khi deploy xong. `pytest tests/test_cp5.py` đọc file này
> để tìm địa chỉ service của bạn và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị API key vào đây.**
> Repo này công khai — dán khóa vào là mất khóa.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Bùi Gia Chính |
| Mã học viên | 2A202602693 |
| Repo | https://github.com/inosukeke/K4-L3A-DAY12-BuiGiaChinh-2A202602693-CloudServicesAndDeployment |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://agent-production-ba73.up.railway.app |
| Platform | Railway (project `sweet-trust`, service `agent` build từ `Dockerfile`, region US West) |
| Ngày deploy | 2026-09-28 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | Railway tự gán — không set tay; container đọc qua `${PORT:-8000}` |
| `AGENT_API_KEY` | ✅ | đặt bằng Railway Variables (CLI), không nằm trong repo / image |
| `REDIS_URL` | ✅ | Redis add-on của Railway, tham chiếu `${{Redis.REDIS_URL}}` (mạng private) |
| `RATE_LIMIT_PER_MINUTE` | ✅ | 10 |
| `MONTHLY_BUDGET_USD` | ✅ | 10.0 |
| `LOG_LEVEL` | ✅ | INFO |

## Lệnh Kiểm Tra

Thay `<URL>` bằng Public URL ở trên:

```bash
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i <URL>/health

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i <URL>/ready

# 3. Không có API key — mong đợi 401
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"Hello"}'

# 4. Có API key — mong đợi 200 kèm câu trả lời
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AGENT_API_KEY" \
  -H "X-User-Id: sv-test" \
  -d '{"question":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/ask \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $AGENT_API_KEY" \
    -H "X-User-Id: sv-test" \
    -d '{"question":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Chạy lúc 2026-09-28 16:19 UTC với `<URL>` = https://agent-production-ba73.up.railway.app

```
$ curl -i <URL>/health
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"ok","service":"day12-agent","version":"1.0.0"}

$ curl -i <URL>/ready
HTTP/1.1 200 OK
Content-Type: application/json

{"status":"ready","redis":true}

$ curl -i -X POST <URL>/ask -H "Content-Type: application/json" -d '{"question":"Hello"}'
HTTP/1.1 401 Unauthorized
www-authenticate: ApiKey

{"detail":"invalid or missing API key"}

$ curl -i -X POST <URL>/ask ... -H "X-API-Key: <key>" -H "X-User-Id: sv-test" -d '{"question":"Deploy là gì?"}'
HTTP/1.1 200 OK

{"answer": "Câu hỏi hay. Deploy là gì thường được giải quyết bằng cách chuẩn hóa môi trường chạy: cùng một image chạy giống nhau ở laptop và trên cloud.", "user_id": "sv-test", "history_length": 0, "cost_usd": 2.145e-05, "tokens": {"in": 3, "out": 35}}

$ # rate limit — 15 request liên tiếp, cùng user
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429
```

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/railway-status.png` — `railway status` / `deployment list` / tên biến: service `agent` và `Redis` đều Online, deploy SUCCESS
- `screenshots/health.png` — `curl -i` tới `/health` (200), `/ready` (200, redis=true), `/ask` không key (401) trên public URL

---

Không dùng phương án dự phòng — service chạy thật trên Railway.
