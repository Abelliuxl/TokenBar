# TokenBar 项目约定

## 修改后的本机验证

- 用户要求：以后修改 TokenBar 的可运行代码后，完成构建和必要验证，就直接替换当前正在运行的安装版，让用户能立即验证；不要只留下 `build/TokenBar.app`。
- 安装位置为 `/Applications/TokenBar.app`。先确认构建成功和签名有效，再备份原安装版，正常结束其进程，复制新应用到该路径并启动。
- 替换后检查 `/Applications/TokenBar.app/Contents/MacOS/TokenBar` 的进程确实运行，且安装版可执行文件与本次构建产物一致。失败时恢复备份并报告原因。
- 如任务涉及交付安装包，同时生成并校验 ZIP。不要覆盖或删除用户的登录态、Keychain 凭证与设置。
- 用户明确要求只修改源码或暂不安装时，遵从该次要求。
