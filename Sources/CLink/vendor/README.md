# 固定的第三方源码

Ableton Link 4.1.1，提交 `5ba907ae027a8c2ec8824463e37296dcefc5e9be`，来源 https://github.com/Ableton/link 。仅使用 Link.hpp，不使用 Link Audio。
Asio 来自该版本子模块，提交 `8806a6803cde7054c3049d3666d3ec36786568c5`，来源 https://github.com/chriskohlhoff/asio 。
头文件及授权未经修改。Link 为 GPLv2+ / 专有许可双授权，Asio 为 Boost Software License 1.0。本目录保留第三方原始授权；主项目采用 GPL-2.0-or-later，Link 集成产物按 GPL 路线分发，见根目录 LICENSE 与 COPYING.md。

依赖必要性：复用官方网络发现、拍点映射与漂移补偿实现，不自行实现同步协议。保留本地源码以固定构建输入，构建不联网下载。
