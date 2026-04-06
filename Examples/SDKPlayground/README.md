# SDK Playground

Интерактивное iOS-приложение **внутри репозитория SDK** для быстрой проверки `XMPPChatCore` + `XMPPChatUI`: ввод окружения (Base URL, app token, XMPP), вход по **JWT** (`/users/client`) или **email/password** (`/users/login-with-email`), затем чат и вкладка **Logs** (события XMPP из `NotificationCenter`).

> Название **SDKPlayground** намеренно не `Testing`, чтобы не путать с unit/UI-тестами.

## Сборка

Из каталога `Examples/SDKPlayground`:

```bash
./generate_xcodeproj.sh
open SDKPlayground.xcodeproj
```

**Важно:** не вызывайте только `xcodegen generate` без следующего шага — XcodeGen не прописывает связь `package` у локального SPM, и Xcode показывает *Missing package product 'XMPPChatCore' / 'XMPPChatUI'*. Скрипт `generate_xcodeproj.sh` запускает `xcodegen` и затем `fix_local_package_refs.py`.

Выберите схему **SDKPlayground** и симулятор. Локальный пакет подключается как `path: ../..` (корень `ethora-sdk-swift`).

Проект **должен** открываться из `ethora-sdk-swift/Examples/SDKPlayground/`. Если скопировать только папку `SDKPlayground` в другой репозиторий без корня пакета, относительный путь `../..` к `Package.swift` сломается — тогда нужно поправить путь к локальному пакету в Xcode.

## Вкладки

| Вкладка | Назначение |
|--------|------------|
| **Setup** | Параметры API и XMPP, режим авторизации, **Connect** / **Disconnect** |
| **Chat** | `ChatWrapperView` после успешного Connect |
| **Logs** | Лента событий (в т.ч. `XMPPConnectionStatusChanged`, `XMPPClientDidConnect`, …) |

Форма сохраняется в `UserDefaults` (включая пароль — только для локальной отладки).

## Пересборка проекта

После правок `project.yml`:

```bash
./generate_xcodeproj.sh
```
