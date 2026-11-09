# Сборка с Windows и установка на iPhone

## На свой iPhone с обычным Apple Account

1. Откройте успешный запуск **WakeGuard iOS** в GitHub Actions. В разделе **Artifacts** скачайте **WakeGuard-iPhone** и извлеките `WakeGuard.ipa` из ZIP. Для скачивания через GitHub войдите в свой аккаунт. [Запуски проекта](https://github.com/dimakovery-art/WakeGuard/actions/workflows/ios.yml)
2. На Windows установите Sideloadly. На странице загрузки в разделе **Before you install** есть ссылки на требуемые настольные версии iTunes и iCloud. [Сайт Sideloadly](https://sideloadly.io/)
3. Подключите разблокированный iPhone к ПК по USB и подтвердите «Доверять этому компьютеру». Откройте Sideloadly, выберите свой iPhone, перетащите в окно `WakeGuard.ipa`, введите свой Apple Account и нажмите **Start**. Пройдите вход и двухфакторную проверку, если их запросит программа. Сохраните расширение WakeGuardActivity, если появится выбор расширений.
4. Если iOS попросит доверять разработчику, откройте **Настройки → Основные → VPN и управление устройством**, выберите профиль своей учётной записи и подтвердите доверие. Для запуска локально подписанных приложений включите **Настройки → Конфиденциальность и безопасность → Режим разработчика**, перезагрузите iPhone и подтвердите включение. [Режим разработчика Apple](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
5. Откройте WakeGuard, поставьте пробный подъём на несколько минут вперёд, разрешите будильники и заблокируйте экран. Проверьте звук и повтор. Установка и звонок на конкретном устройстве требуют такой проверки.

Бесплатная подпись действует **7 дней**. Для продления включите автоматическое обновление в Sideloadly и периодически подключайте iPhone к ПК с работающим Sideloadly по USB или настроенному Wi-Fi. При ручном обновлении используйте тот же Apple Account и идентификатор приложения. [Ограничения Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account) · [Обновление через Sideloadly](https://sideloadly.io/faq.html)

## 1. Проверка через GitHub Actions

Эта часть собирает приложение и расширение под устройство, затем запускает XCTest на iPhone Simulator. Подпись для физического устройства здесь отключена. Покупка участия в Apple Developer Program для проверки сборки не требуется.

1. Распакуйте архив. Откройте в PowerShell папку, где одновременно лежат `WakeGuard.xcodeproj`, `.github` и `codemagic.yaml`.
2. Создайте пустой репозиторий GitHub. У стандартных GitHub-hosted runners в публичных репозиториях минуты бесплатны. Для закрытого репозитория предварительно посмотрите оставшуюся квоту своего тарифа. [Условия GitHub Actions](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
3. Если используете GitHub Desktop, выберите **File → Add local repository** и создайте репозиторий в распакованной папке, сделайте первый commit и нажмите **Publish repository**. Вариант через Git для Windows приведён ниже. Подставьте свой адрес репозитория.

```powershell
git init -b main
git add .
git commit -m "WakeGuard для iPhone"
git remote add origin https://github.com/YOUR-ACCOUNT/WakeGuard.git
git push -u origin main
```

4. Откройте **Actions → WakeGuard iOS**. При необходимости включите Actions в настройках репозитория. На push запускаются два задания. Повторный ручной запуск доступен через **Run workflow** в основной ветке.
5. В каждом задании проверьте шаги **Xcode and iPhone SDK** и **Test on iPhone simulator**. Первый компилирует Release для `generic/platform=iOS`. Второй компилирует Debug и запускает тесты. Скачайте артефакт `XCTest-iOS-26` или `XCTest-iOS-27` с результатом `.xcresult`. Название установленной версии SDK видно в начале журнала. При изменении образов GitHub сверяйте метки runner и доступные среды. [Образы GitHub](https://github.com/actions/runner-images)

Папка `.github` должна находиться в корне репозитория. Если Actions не видит workflow, проверьте также, что в репозиторий попало содержимое архива.

## 2. Установка через TestFlight без собственного Mac

Для этого пути нужны членство Apple Developer Program, доступ к App Store Connect и облачный сервис подписи. К этой части можно перейти после успешной проверки проекта. Публичный выпуск в App Store для тестирования не требуется. [Аккаунты разработчика Apple](https://developer.apple.com/help/account/basics/about-your-developer-account)

1. Выберите собственный уникальный идентификатор приложения, например `com.myname.wakeguard`. Замените префикс `org.example.wakeguard` в **WakeGuard.xcodeproj/project.pbxproj** и **codemagic.yaml** во всех вхождениях. У расширения должен получиться идентификатор с суффиксом `.activity`. Сохраните изменения в GitHub.
2. В Apple Developer → **Certificates, Identifiers & Profiles → Identifiers** зарегистрируйте два явных App ID для приложения и расширения. В App Store Connect → **Apps → + → New App** создайте запись для iOS, выберите русский основной язык, App ID приложения и свой SKU.
3. В App Store Connect → **Users and Access → Integrations → App Store Connect API** создайте ключ команды с правами, достаточными для подписи и загрузки (для описанного процесса Codemagic указывает App Manager). Скачайте файл `.p8`, сохраните **Issuer ID** и **Key ID**. В Codemagic → **Team settings → Team integrations → Developer Portal** добавьте ключ под именем **WakeGuard**. Это имя указано в YAML.
4. В Codemagic → **Code signing identities → iOS certificates** создайте **Apple Distribution** через подключённый ключ либо загрузите имеющийся сертификат `.p12` с его закрытым ключом и паролем. При генерации скачайте сертификат и добавьте его в хранилище согласно подсказке сервиса. Сертификат связывает подпись с вашей командой. Ключ API служит для доступа к сервису Apple.
5. На портале Apple в **Profiles → +** создайте два профиля распространения **App Store Connect**. Для каждого выберите соответствующий App ID и тот же сертификат Apple Distribution. В Codemagic → **iOS provisioning profiles** загрузите оба файла `.mobileprovision` или выберите **Fetch profiles**. У обоих профилей должно отображаться совпадение с сертификатом. Файлы ключей и пароли хранятся в сервисе подписи. [Подпись в Codemagic](https://docs.codemagic.io/yaml-code-signing/signing-ios/)
6. Добавьте репозиторий в Codemagic как приложение с конфигурацией YAML. Запустите workflow **WakeGuard TestFlight** из нужной ветки. Он применяет профили, выставляет номер сборки, архивирует схему, экспортирует подписанный IPA и передаёт его в App Store Connect. Если в записи приложения уже есть сборки, поставьте номер выше использованного ранее. Тариф и доступные минуты macOS видны в вашем аккаунте Codemagic. [Нативные iOS-сборки](https://docs.codemagic.io/yaml-quick-start/building-a-native-ios-app/)
7. Дождитесь обработки в App Store Connect → **TestFlight**. При появлении вопросов о шифровании ответьте по фактическому составу своей сборки. Создайте группу внутренних тестировщиков, добавьте сборку и свою учётную запись App Store Connect с доступом к приложению.
8. На iPhone установите **TestFlight** из App Store, откройте приглашение и нажмите **Установить**. Затем создайте короткий дневной план и проверьте регистрацию и фактическое срабатывание по [протоколу](TESTING.md).

**Для друзей** создайте группу внешних тестировщиков в TestFlight, заполните описание беты и контактные данные, добавьте сборку и отправьте её на TestFlight App Review, когда это предложит Apple. После допуска сборки отправьте приглашения из группы или включите публичную ссылку. Для этого способа UDID друзей не нужны. Срок тестирования каждой сборки — до 90 дней. [Руководство Apple по TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## 3. Другие варианты

| Путь | Когда подходит | Что потребуется |
| --- | --- | --- |
| GitHub Actions | Разработка с Windows и проверка изменений | Репозиторий и доступные минуты macOS. Текущий workflow собирает без подписи для устройства. |
| Codemagic + TestFlight | Установка себе и друзьям с Windows | Apple Developer Program, два профиля, сертификат и подключение App Store Connect. Конфигурация входит в проект. |
| Xcode Cloud | Вы используете инфраструктуру Apple | Членство в программе, подключённый репозиторий, запись приложения. Первичную настройку workflow начинают в Xcode на доступном Mac, в том числе арендованном. Добавьте действие Archive и распространение через TestFlight. [Xcode Cloud](https://developer.apple.com/xcode-cloud/) |
| Personal Team | Краткая бесплатная проба с доступом к Mac и iPhone | Войдите в Xcode с Apple Account, выберите свою команду и уникальные Bundle ID для приложения и расширения, подключите iPhone, подтвердите доверие и включите режим разработчика по запросу iOS. Выберите устройство в Xcode и нажмите Run. Для Personal Team профиль действует семь дней, после чего нужно переподписать и переустановить сборку. Удалённому Mac нужен доступ к устройству. [Ограничения Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account) |

Для прямой установки подписанного Development или Ad Hoc IPA нужны соответствующая подпись и профиль с зарегистрированным устройством. Сборку для App Store Connect устанавливают через TestFlight. Для вашего сценария без Mac последовательность из разделов 1 и 2 полностью выполняется через Windows и iPhone.

