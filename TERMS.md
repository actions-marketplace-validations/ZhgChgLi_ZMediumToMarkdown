# Terms of Use

**ZMediumToMarkdown · Terms `v1`**

These Terms govern your use of the `ZMediumToMarkdown` Ruby gem and any related code in this repository (collectively, **"the Software"**). The Software is offered by **ZhgChgLi** (an individual, identified by the GitHub handle [`@ZhgChgLi`](https://github.com/ZhgChgLi); referred to here as **"the Author"**) free of charge under the MIT License.

By installing, running, or otherwise using the Software you agree to these Terms. The CLI will, on its first invocation, print a one-time consent prompt and require an explicit `yes` before performing any network call. If you do not agree, do not use the Software.

---

## 1. What the Software is

The Software is a personal command-line utility, written in Ruby, that converts a Medium post into a Markdown file by issuing HTTP requests to Medium's GraphQL endpoint using cookies that **you supply** from your own browser session. It is open source under MIT, with all source code public on [GitHub](https://github.com/ZhgChgLi/ZMediumToMarkdown).

The Software is **not affiliated with, endorsed by, sponsored by, or connected to** Medium, A Medium Corporation, or any of its subsidiaries.

## 2. Third-party services risk · Medium's Terms of Service

Medium's official rules forbid automated access to its services. The relevant text, quoted from [Medium Rules](https://policy.medium.com/medium-rules-30e5502c4eb4), reads:

> "any software, script, robot, spider or other automatic device, process or means (including crawlers, browser plugins and add-ons or any other technology) to access the Services for any purpose, including without limitation to scrape or otherwise copy any of the data or content on the Services."

The Software is exactly the kind of tool that statement contemplates.

**The Author makes no claim that this use is permitted by Medium.** Using the Software may technically conflict with Medium's Terms of Service. You are using it **at your own risk** and accept full responsibility for any consequence, including but not limited to:

- account warning, suspension, or termination by Medium;
- IP address rate-limiting or blocking;
- legal action by Medium or by the original article author(s);
- loss of access to articles you previously could read.

If you are unsure whether your intended use is acceptable, do not run the Software — use Medium's own official export feature ([Settings → Account → Download your information](https://help.medium.com/hc/en-us/articles/115004551948)) instead.

## 3. Eligibility

You may only use the Software if you are old enough to enter into a binding agreement under the law of the jurisdiction in which you reside (typically thirteen (13) years of age or older, sixteen (16) in some countries, eighteen (18) where the law requires).

## 4. License & open source

The Software is released under the **MIT License**. The full license text is in [`LICENSE`](./LICENSE). The MIT License grants you broad rights to use, copy, modify, and redistribute the Software's source code; it does **not** grant any rights to the article content, images, embeds, or other materials the Software downloads from Medium.

## 5. Your responsibilities

By using the Software you agree that:

1. **Access right.** You only convert articles that you have the legitimate right to read on Medium — typically because the article is publicly accessible, or because you are a Medium Member with active access to the article's metering tier.
2. **Cookies are yours.** Any `sid`, `uid`, `cf_clearance`, or `_cfuvid` value you supply belongs to a Medium account that you yourself control. You will not use someone else's session.
3. **No mass scraping.** You will not use the Software for bulk crawling, building large datasets for resale, training datasets without independent permission from the rights holders, or any commercial redistribution.
4. **Respect copyright.** Any Markdown the Software produces remains the original Medium author's copyrighted work. You will only redistribute, republish, or otherwise share the output where the original author has granted you permission, or where the law of your jurisdiction (fair use, fair dealing, quotation, etc.) clearly permits it.
5. **Your platform, your call.** You are responsible for compliance with Medium's Terms of Service, with applicable computer-fraud and access-control laws, and with any contractual obligation you may have toward third parties (employer policies, NDA, etc.).

## 6. Intellectual property

The Software's source code is © `ZhgChgLi`, licensed under MIT. The article content, images, video stills, code samples, and embeds the Software downloads belong to their respective rights holders. The existence of the Software does not transfer any ownership in those materials and does not imply a license to redistribute them.

## 7. Disclaimer of warranties

THE SOFTWARE IS PROVIDED **"AS IS"** AND **"AS AVAILABLE"**, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, ACCURACY, AND NON-INFRINGEMENT. THE AUTHOR DOES NOT WARRANT THAT:

- the Software will run without errors or interruption;
- the conversion output will be complete, faithful, or lossless;
- the Software complies with Medium's Terms of Service or with any other third party's terms;
- the Software is fit for any particular regulatory environment.

## 8. Limitation of liability

TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, CONSEQUENTIAL, SPECIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR ANY LOSS OF DATA, PROFITS, REVENUE, GOODWILL, OR ARTICLES, ARISING OUT OF OR IN CONNECTION WITH THE SOFTWARE, REGARDLESS OF THE LEGAL THEORY (CONTRACT, TORT, STRICT LIABILITY, OR OTHERWISE) AND EVEN IF THE AUTHOR HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

## 9. Indemnification

You agree to defend, indemnify, and hold harmless the Author from and against any claim, demand, action, loss, or expense (including reasonable attorneys' fees) arising out of or related to:

- your breach of these Terms;
- your breach of Medium's Terms of Service through use of the Software;
- your infringement of any copyright, trade secret, or other right of any third party;
- your use of the Software in any manner that is unlawful in your jurisdiction.

## 10. No support obligation

The Software is offered as a personal open-source project. The Author has no obligation to provide support, fix bugs, accept patches, answer questions, or maintain compatibility with future versions of Medium's API or website. Issues and pull requests on GitHub are reviewed on a best-effort, non-binding basis.

## 11. Modifications & termination

The Author may modify these Terms at any time by publishing a new version in the repository. Material changes are signaled by bumping the `Terms` version string in `lib/Terms.rb`; on the next run, the CLI will print the updated summary and require fresh acceptance before proceeding.

The Author may, at any time and without notice, suspend, archive, or remove the Software (including unpublishing the gem from RubyGems and archiving the GitHub repository). You will not be entitled to any compensation if this occurs.

## 12. Governing law & dispute resolution

The Software is provided **as-is** under the MIT License. **No specific jurisdiction is asserted.** Disputes arising from your use of the Software are governed by the law of the jurisdiction in which **you** reside, applied to the MIT License's existing "AS IS" provisions and to the disclaimers in Sections 7 – 9 above. The Author has no obligation to litigate, defend, or appear in any forum, and reserves the right to do nothing in response to any claim.

Where mandatory consumer-protection or copyright law of your jurisdiction grants you rights that cannot be waived by these Terms, those rights are unaffected.

## 13. Severability

If any provision of these Terms is held invalid or unenforceable by a court of competent jurisdiction, that provision will be limited or removed to the minimum extent necessary, and the remainder of the Terms will continue in full force.

## 14. Contact

The only supported channel for questions, takedown notices, or legal inquiries about the Software itself is GitHub Issues:

> [https://github.com/ZhgChgLi/ZMediumToMarkdown/issues](https://github.com/ZhgChgLi/ZMediumToMarkdown/issues)

For concerns about specific Medium articles or accounts, contact Medium directly — the Author does not host, store, or distribute Medium content.

---

**Last updated:** 2026-05-10
**Version:** `v1`
