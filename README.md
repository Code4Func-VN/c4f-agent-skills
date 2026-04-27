# c4f-agent-skills

Bộ sưu tập Claude Code skills cho quy trình phát triển phần mềm. Mỗi skill nằm trong `skills/<name>/SKILL.md` và được Claude Code tải lên khi điều kiện kích hoạt phù hợp.

## Skill hoạt động như thế nào

Một skill là file markdown có phần YAML frontmatter khai báo với Claude Code:
- **name** — tên định danh của skill
- **description** — điều kiện kích hoạt (Claude đọc trường này để quyết định có dùng skill không)
- **allowed-tools** — danh sách tool mà skill được phép gọi
- **disable-model-invocation** — nếu `true`, nội dung skill được inject thẳng vào system prompt mà không tốn thêm LLM call

Phần thân của skill là nội dung hướng dẫn mà Claude tuân theo khi skill đang active. Skill có thể tham chiếu các file đi kèm trong thư mục con `references/`, `scripts/`, hoặc `assets/`.

**Cài đặt skill:** Copy thư mục skill vào `.claude/skills/<name>/` trong project (hoặc `~/.claude/skills/<name>/` để dùng toàn cục), rồi khai báo trong `claude.json`:

```json
{
  "skills": ["<name>"]
}
```

---

## Danh sách skills

### Git & quản lý version

#### `git`
**Dùng khi:** Có bất kỳ thay đổi code nào — viết mới, sửa, hoặc xóa.

Tự động commit theo conventional commits (`feat:`, `fix:`, `refactor:`…), chạy security scan trước khi commit, và có thể mở pull request. Cũng có thể gọi trực tiếp bằng `/git pr` hoặc `/git scan`.

References: chiến lược branch, quy ước commit, giải quyết conflict, quy trình PR, security scanning.

---

#### `git-guardrails-claude-code`
**Dùng khi:** Muốn ngăn Claude vô tình chạy các lệnh git nguy hiểm.

Cài đặt hook `PreToolUse` để chặn các lệnh: `git push`, `git reset --hard`, `git clean -f/fd`, `git branch -D`, `git checkout .`, `git restore .`. Hỗ trợ cài theo project hoặc toàn cục.

Kèm theo: `scripts/block-dangerous-git.sh` — script hook được cài vào hệ thống.

---

### Go backend

#### `go-engineer`
**Dùng khi:** Viết, review, test, hoặc scaffold code Go.

Áp dụng Go idiomatic style (clarity → simplicity → concision), quy ước xử lý lỗi (`fmt.Errorf("save user: %w", err)`), clean architecture với Echo + GORM + Docker, và kỷ luật viết test trước code. Chặn commit `feat`/`fix` nếu không có test.

References: API design, cấu trúc project, concurrency, database patterns, error handling, testing theo layer, linting, logging, performance, checklist code review.

Scripts: scaffold project, cài lint, kiểm tra naming/error/interface, so sánh benchmark, pre-review tự động.

---

### Ant Design / React UI

#### `ant-design`
**Dùng khi:** Ra quyết định về antd 6.x, Ant Design Pro, hoặc Ant Design X — chọn component, theming, SSR, a11y, performance, CRUD, AI/chat UI.

Guide ra quyết định (không phải tutorial). Theo framework SPOT: Scope → Process → Output. Bắt buộc query `@ant-design/cli` trước khi viết bất kỳ component nào. Quy tắc cứng: một `ConfigProvider` duy nhất ở root, theming ưu tiên token, không dùng selector `.ant-*`.

References: `antd-cli.md` — quy trình CLI offline để tra API, demo, migration, lint, báo bug.

---

#### `antd`
**Dùng khi:** Viết antd component, debug lỗi antd, tra API/props/token/demo, migrate giữa các version, hoặc phân tích antd usage trong project.

Skill tập trung vào CLI. Yêu cầu `@ant-design/cli` (`which antd || npm install -g @ant-design/cli`). Bao phủ 10 tình huống: viết component, xem docs đầy đủ, debug, migration, phân tích project, changelog, khám phá component, báo bug component, báo bug CLI, chạy MCP server. Luôn dùng `--format json`.

---

### Kiến trúc & thiết kế

#### `improve-codebase-architecture`
**Dùng khi:** Muốn cải thiện kiến trúc, tìm cơ hội refactor, làm codebase dễ test hơn hoặc dễ navigate hơn cho AI.

Tìm **deepening opportunities** — các refactor biến module nông (interface phức tạp, implementation mỏng) thành module sâu (interface nhỏ, implementation dày). Dùng vocabulary của Ousterhout: module, interface, depth, seam, adapter, leverage, locality. Ba bước: Explore → Đề xuất candidates → Grilling loop. Đọc `CONTEXT.md` và `docs/adr/` để lấy ngôn ngữ domain.

File đi kèm:
- `DEEPENING.md` — cách phân loại dependency và test qua seam
- `INTERFACE-DESIGN.md` — pattern dùng parallel sub-agent để khám phá interface thay thế
- `LANGUAGE.md` — vocabulary dùng chung (phải dùng chính xác các thuật ngữ này)

Kết hợp tốt với: `domain-model`, `design-an-interface`.

---

#### `design-an-interface`
**Dùng khi:** Thiết kế API, khám phá các phương án interface, so sánh hình dạng module, hoặc khi muốn "design it twice".

Spawn 3+ sub-agent song song, mỗi agent nhận một ràng buộc thiết kế khác nhau (tối giản số method / tối đa linh hoạt / tối ưu cho case phổ biến nhất). Trình bày từng thiết kế, rồi so sánh theo depth, locality, và khả năng dùng đúng. Dựa trên nguyên tắc "Design It Twice" của Ousterhout.

---

#### `domain-model`
**Dùng khi:** Stress-test plan trước ngôn ngữ domain của project, làm rõ thuật ngữ, quản lý `CONTEXT.md` và ADR.

Thực hiện phiên grilling không nhượng bộ: thách thức các thuật ngữ mơ hồ, đối chiếu code với hành vi đã nêu, cập nhật `CONTEXT.md` ngay khi thuật ngữ được chốt, chỉ đề xuất ADR khi quyết định khó đảo ngược, gây ngạc nhiên nếu không có context, và là kết quả của trade-off thực sự.

File đi kèm:
- `CONTEXT-FORMAT.md` — định dạng và quy tắc viết `CONTEXT.md` (single vs multi-context repo)
- `ADR-FORMAT.md` — định dạng ADR tối giản với tiêu chí khi nào nên viết

---

### Quy trình phát triển

#### `tdd`
**Dùng khi:** Xây dựng tính năng hoặc fix bug theo TDD, red-green-refactor, hoặc test-first.

Áp dụng vertical slices (một test → một implementation → lặp lại), không phải horizontal slices (viết hết test rồi mới viết hết code). Test chỉ được verify behavior qua public interface — không mock internal collaborator, không test private method. Chỉ refactor sau khi đã GREEN.

Reference files:
- `deep-modules.md` — interface nhỏ + implementation lớn (Ousterhout)
- `interface-design.md` — nhận dependency vào, trả về kết quả, surface nhỏ
- `mocking.md` — chỉ mock ở system boundary; ưu tiên SDK-style interface
- `refactoring.md` — duplication, shallow module, feature envy, primitive obsession
- `tests.md` — ví dụ test tốt vs test xấu với các red flag

---

#### `grill-me`
**Dùng khi:** Muốn stress-test một plan, bị thách thức về quyết định thiết kế, hoặc khi gõ "grill me".

Phỏng vấn bạn không ngừng về mọi khía cạnh của plan — một câu hỏi mỗi lần, đi theo từng nhánh của cây quyết định. Đưa ra câu trả lời được đề xuất cho mỗi câu hỏi. Tự khám phá codebase để trả lời những câu hỏi có thể tìm thấy trong code.

---

#### `zoom-out`
**Dùng khi:** Không quen với một phần code và cần hiểu nó fit vào bức tranh lớn như thế nào.

Skill một dòng: yêu cầu agent lên một tầng abstraction và tạo ra bản đồ tất cả các module và caller liên quan. Không tốn LLM call (`disable-model-invocation: true`).

---

## Thêm skill mới

1. Tạo `skills/<name>/SKILL.md` với frontmatter schema ở trên.
2. Thêm reference files vào `skills/<name>/references/` hoặc `skills/<name>/scripts/` nếu cần.
3. Viết trường `description` thật chính xác — Claude dùng nó để quyết định khi nào kích hoạt skill.
4. Test với một task thực tế trước khi commit.
