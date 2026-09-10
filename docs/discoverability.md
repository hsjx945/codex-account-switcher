# Search and AI discovery / 搜索与 AI 检索

## English

The public website is designed to help search engines and AI search systems discover and understand this macOS Codex account switcher. English and Simplified Chinese pages explain installation, authorized-account switching, local storage, usage windows, and limitations in readable HTML. They link to source code and release artifacts rather than relying on keyword repetition.

Implemented discovery foundations:

- Crawlable static HTML, one descriptive H1 and a distinct title/description per page.
- Self-referencing canonical URLs and reciprocal English/Chinese `hreflang` links.
- A sitemap covering every public page and permissive page-level robots metadata. The included `robots.txt` is a deployment aid: on GitHub project Pages, only the host-root `/robots.txt` controls crawlers, so its live policy must be checked separately.
- JSON-LD software/project facts consistent with visible content and the release version.
- Open Graph metadata for sharing and a bilingual `llms.txt` source map for readers and tools that choose to use it.

These measures support discoverability; they do **not** prove indexing, ranking, AI citations, or traffic growth. `llms.txt` is an optional source map, not a Google ranking requirement. Google says its AI search features use the same SEO foundations and do not require special AI files or schema.

After deployment, verify live pages return HTTP 200, inspect the sitemap and language links, and use a verified Search Console property to request indexing and measure impressions/clicks. Compare the same date windows before and after publication. Track actual download counts separately from search impressions. No search-engine submission, property verification, or traffic increase is claimed merely because repository checks pass.

## 简体中文

公开网站面向搜索引擎和 AI 检索提供清晰、可引用的项目资料。中英文页面使用可直接读取的 HTML，解释 macOS Codex 多账号切换、安装、本机存储、额度窗口和使用限制，并链接源码与 Release，帮助用户找到与确认项目。

已实现：静态正文、独立标题与摘要、唯一 H1、规范网址、中英双语互链、覆盖公开页面的 sitemap、允许索引的页面元数据和 robots.txt 部署参考、与正文和版本一致的 JSON-LD、分享预览，以及供愿意读取它的工具使用的双语 llms.txt。

**可抓取不等于已收录，更不等于排名、AI 引用或流量已经增加。** llms.txt 只是补充资料索引；Google 的 AI 搜索功能沿用 SEO 基础，不要求额外的 AI 文件或特殊结构化数据。

GitHub 项目站点部署在子路径时，只有域名根路径 `/robots.txt` 才控制抓取；项目子目录里的同名文件不能代替它。上线后需要检查真实网址返回 HTTP 200，并在拥有权限的 Search Console 站点中检查收录、提交 sitemap、观察展示量与点击量。使用相同长度的前后时间窗口比较变化，下载量另行统计。仅通过本地检查不能宣称已经提交搜索引擎或获得流量增长。

## Primary sources / 一手来源

- [Google: AI features and your website](https://developers.google.com/search/docs/appearance/ai-features)
- [Google: Sitemaps overview](https://developers.google.com/search/docs/crawling-indexing/sitemaps/overview)
- [Google: Localized versions of your pages](https://developers.google.com/search/docs/specialty/international/localized-versions)

## Verification / 验证

Run `node scripts/check-site-geo.mjs` from the repository root. This checks metadata, links, language pairs, software versions, and sitemap coverage; it does not query a search index. Publication and live-site checks must be reported separately.
