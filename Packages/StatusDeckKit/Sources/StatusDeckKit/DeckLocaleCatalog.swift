// The English label is the lookup key. Keep format placeholders intact.
enum DeckLocaleCatalog {
    static let values: [DeckLanguage: [String: String]] = {
        let languages: [DeckLanguage] = [.french, .german, .japanese, .korean]
        var result: [DeckLanguage: [String: String]] = [:]
        for row in rows.split(separator: "\n") {
            let columns = row.split(separator: "|", omittingEmptySubsequences: false)
            guard columns.count == languages.count + 1 else { continue }
            for (language, translation) in zip(languages, columns.dropFirst()) where !translation.isEmpty {
                result[language, default: [:]][String(columns[0])] = String(translation)
            }
        }
        return result
    }()

    private static let rows = #"""
System default|Langue du système|Systemsprache|システムに従う|시스템 언어 따르기
Interface language|Langue de l’interface|Oberflächensprache|表示言語|인터페이스 언어
Language|Langue|Sprache|言語|언어
Your desktop, together|Tout votre bureau au même endroit|Alles für deinen Schreibtisch|デスクトップをひとつに|데스크탑을 한곳에서
Preferences|Réglages|Einstellungen|設定|설정
General|Général|Allgemein|一般|일반
Appearance|Apparence|Erscheinungsbild|外観|모양
Light|Clair|Hell|ライト|라이트
Dark|Sombre|Dunkel|ダーク|다크
Follow system appearance|Suivre l’apparence du système|Systemdarstellung verwenden|システムの外観に従う|시스템 모양 따르기
Liquid Glass|Liquid Glass|Liquid Glass|Liquid Glass|Liquid Glass
Frosted appearance|Verre dépoli|Milchglas|すりガラス|반투명 유리
Card translucency|Transparence des cartes|Kartentransparenz|カードの透明度|카드 투명도
Background depth|Profondeur de l’arrière-plan|Hintergrundtiefe|背景の深さ|배경 깊이
Background blur|Flou de l’arrière-plan|Hintergrundunschärfe|背景のぼかし|배경 흐림
Pointer glow|Halo du pointeur|Zeigerlicht|ポインタの光彩|포인터 빛 효과
Background depth controls the gray tint. Background blur softens desktop details.|La profondeur règle la teinte grise. Le flou adoucit les détails du bureau.|Die Hintergrundtiefe regelt die graue Tönung. Die Hintergrundunschärfe zeichnet Desktopdetails weich.|背景の深さはグレーの色合いを調整します。背景のぼかしでデスクトップの細部をやわらげます。|배경 깊이는 회색 농도를 조절합니다. 배경 흐림은 데스크탑의 세부를 부드럽게 표시합니다.
Background translucency|Transparence de l’arrière-plan|Hintergrundtransparenz|背景の透明度|배경 투명도
Light intensity|Intensité lumineuse|Lichtintensität|光の強さ|빛 강도
Live material preview|Aperçu en direct|Live-Vorschau|リアルタイムプレビュー|실시간 미리보기
Launch at login|Ouvrir à la connexion|Bei Anmeldung öffnen|ログイン時に起動|로그인 시 실행
Refresh interval|Intervalle d’actualisation|Aktualisierungsintervall|更新間隔|새로 고침 간격
1 second|1 seconde|1 Sekunde|1 秒|1초
2 seconds|2 secondes|2 Sekunden|2 秒|2초
5 seconds|5 secondes|5 Sekunden|5 秒|5초
Show uptime on the main panel|Afficher la durée de fonctionnement dans le panneau principal|Laufzeit im Hauptpanel anzeigen|メインパネルに稼働時間を表示|메인 패널에 가동 시간 표시
Uptime|Durée de fonctionnement|Laufzeit|稼働時間|가동 시간
Sections · Drag to reorder|Rubriques · Glisser pour réorganiser|Bereiche · Zum Sortieren ziehen|項目 · ドラッグして並べ替え|항목 · 드래그하여 순서 변경
Controls|Commandes|Steuerung|コントロール|제어
Monitoring|Surveillance|Überwachung|モニタリング|모니터링
Tools|Outils|Werkzeuge|ツール|도구
Menu bar|Barre des menus|Menüleiste|メニューバー|메뉴 막대
Menu bar readings|Mesures dans la barre des menus|Messwerte in der Menüleiste|メニューバーに測定値を表示|메뉴 막대에 측정값 표시
Combined status icon|Icône d’état combinée|Kombiniertes Statussymbol|統合ステータスアイコン|통합 상태 아이콘
Plugins|Modules|Plug-ins|プラグイン|플러그인
Extensions|Extensions|Erweiterungen|拡張機能|확장 프로그램
Built-in plugin|Module intégré|Integriertes Plug-in|内蔵プラグイン|내장 플러그인
Plugin updates|Mises à jour des modules|Plug-in-Updates|プラグインのアップデート|플러그인 업데이트
GitHub plugin updates|Mises à jour des modules via GitHub|Plug-in-Updates über GitHub|GitHub プラグインのアップデート|GitHub 플러그인 업데이트
Plugins and settings|Modules et réglages|Plug-ins und Einstellungen|プラグインと設定|플러그인 및 설정
Plugins and settings…|Modules et réglages…|Plug-ins und Einstellungen …|プラグインと設定…|플러그인 및 설정…
Enabled|Activé|Aktiviert|有効|활성화
Permissions|Autorisations|Berechtigungen|権限|권한
Options|Options|Optionen|オプション|옵션
Quit MyStatus|Quitter MyStatus|MyStatus beenden|MyStatus を終了|MyStatus 종료
Open plugins folder|Ouvrir le dossier des modules|Plug-in-Ordner öffnen|プラグインフォルダを開く|플러그인 폴더 열기
Rescan|Analyser à nouveau|Erneut suchen|再スキャン|다시 검색
Check plugin updates|Vérifier les mises à jour des modules|Nach Plug-in-Updates suchen|プラグインのアップデートを確認|플러그인 업데이트 확인
Check all|Tout vérifier|Alle prüfen|すべて確認|모두 확인
Check|Vérifier|Prüfen|確認|확인
Updates|Mises à jour|Updates|アップデート|업데이트
Up to date|À jour|Aktuell|最新|최신 상태
Latest commit|Dernier commit|Neuester Commit|最新コミット|최신 커밋
Current commit|Commit actuel|Aktueller Commit|現在のコミット|현재 커밋
Build update|Compiler la mise à jour|Update erstellen|アップデートをビルド|업데이트 빌드
Building plugin…|Compilation du module…|Plug-in wird erstellt …|プラグインをビルド中…|플러그인 빌드 중…
Fetching GitHub source…|Récupération du code depuis GitHub…|Quellcode wird von GitHub geladen …|GitHub からソースを取得中…|GitHub에서 소스 가져오는 중…
Verifying plugin…|Vérification du module…|Plug-in wird überprüft …|プラグインを検証中…|플러그인 확인 중…
Upstream update available|Mise à jour disponible à la source|Upstream-Update verfügbar|上流のアップデートあり|원본 프로젝트 업데이트 있음
Rebuild and install|Recompiler et installer|Neu erstellen und installieren|再ビルドしてインストール|다시 빌드하여 설치
Roll back|Revenir à la version précédente|Vorherige Version wiederherstellen|以前のバージョンに戻す|이전 버전으로 되돌리기
Open Plugin Updates|Ouvrir les mises à jour des modules|Plug-in-Updates öffnen|プラグインのアップデートを開く|플러그인 업데이트 열기
No extensions installed|Aucune extension installée|Keine Erweiterungen installiert|拡張機能がインストールされていません|설치된 확장 프로그램 없음
Extension · version %@|Extension · version %@|Erweiterung · Version %@|拡張機能 · バージョン %@|확장 프로그램 · 버전 %@
Enable the extension “%@”?|Activer l’extension « %@ » ?|Erweiterung „%@“ aktivieren?|拡張機能「%@」を有効にしますか？|‘%@’ 확장 프로그램을 활성화할까요?
Sound|Son|Ton|サウンド|사운드
Input|Entrée|Eingabe|入力|입력
Output|Sortie|Ausgabe|出力|출력
Software volume|Volume logiciel|Software-Lautstärke|ソフトウェア音量|소프트웨어 음량
Turn off software volume|Désactiver le volume logiciel|Software-Lautstärke deaktivieren|ソフトウェア音量をオフにする|소프트웨어 음량 끄기
Display volume control|Réglage du volume de l’écran|Monitor-Lautstärkeregelung|ディスプレイの音量調整|디스플레이 음량 제어
DDC volume|Volume DDC|DDC-Lautstärke|DDC 音量|DDC 음량
Prefer DDC|Privilégier DDC|DDC bevorzugen|DDC を優先|DDC 우선
Prefer software volume|Privilégier le volume logiciel|Software-Lautstärke bevorzugen|ソフトウェア音量を優先|소프트웨어 음량 우선
Recheck display DDC volume|Vérifier à nouveau le volume DDC|DDC-Lautstärke erneut prüfen|DDC 音量を再確認|DDC 음량 다시 확인
Displays|Écrans|Displays|ディスプレイ|디스플레이
Display brightness control|Réglage de la luminosité de l’écran|Displayhelligkeit regeln|ディスプレイの輝度調整|디스플레이 밝기 제어
Resolution|Résolution|Auflösung|解像度|해상도
Software dimming|Atténuation logicielle|Software-Dimmung|ソフトウェア減光|소프트웨어 디밍
Automatic|Automatique|Automatisch|自動|자동
Automatic (prefer hardware DDC)|Automatique (priorité au DDC matériel)|Automatisch (Hardware-DDC bevorzugen)|自動（ハードウェア DDC を優先）|자동(하드웨어 DDC 우선)
Detect displays again|Détecter à nouveau les écrans|Displays erneut erkennen|ディスプレイを再検出|디스플레이 다시 감지
Retry brightness hardware|Réessayer le réglage matériel de la luminosité|Hardware-Helligkeitsregelung erneut versuchen|ハードウェア輝度調整を再試行|하드웨어 밝기 제어 다시 시도
No displays found|Aucun écran détecté|Keine Displays erkannt|ディスプレイが見つかりません|디스플레이가 감지되지 않음
Built-in|Intégré|Integriert|内蔵|내장
Brightness and volume keys|Touches de luminosité et de volume|Helligkeits- und Lautstärketasten|輝度キーと音量キー|밝기 및 음량 키
Media keys|Touches multimédias|Medientasten|メディアキー|미디어 키
Handle standard F1 / F2|Utiliser les touches F1 et F2 standard|Standardtasten F1 und F2 übernehmen|標準の F1・F2 キーを使う|표준 F1 및 F2 키 사용
Prefer an external display|Privilégier un écran externe|Externes Display bevorzugen|外部ディスプレイを優先|외장 디스플레이 우선
Backup brightness shortcuts ⌃⌥↓ / ⌃⌥↑|Raccourcis de luminosité de secours ⌃⌥↓ / ⌃⌥↑|Alternative Helligkeitskurzbefehle ⌃⌥↓ / ⌃⌥↑|予備の輝度ショートカット ⌃⌥↓ / ⌃⌥↑|대체 밝기 단축키 ⌃⌥↓ / ⌃⌥↑
Test brightening|Tester l’augmentation de la luminosité|Aufhellen testen|明るくするテスト|밝기 높이기 테스트
Test dimming|Tester la réduction de la luminosité|Abdunkeln testen|暗くするテスト|밝기 낮추기 테스트
Current display|Écran actuel|Aktuelles Display|現在のディスプレイ|현재 디스플레이
Reconnect keys|Réactiver l’écoute des touches|Tastenerkennung neu verbinden|キーの監視を再接続|키 수신 다시 연결
Receiving key events|Réception des frappes|Tastenereignisse werden empfangen|キー入力を受信中|키 이벤트 수신 중
Key listener enabled|Écoute des touches activée|Tastenerkennung aktiv|キーの監視が有効|키 수신 활성화
Last brightness key: |Dernière touche de luminosité : |Letzte Helligkeitstaste: |最後の輝度キー：|마지막 밝기 키: 
Handled|Interception réussie|Verarbeitet|処理済み|처리됨
Passed to macOS|Transmis à macOS|An macOS übergeben|macOS に渡しました|macOS로 전달됨
Accessibility permission required|Autorisation d’accessibilité requise|Bedienungshilfen-Berechtigung erforderlich|アクセシビリティ権限が必要です|손쉬운 사용 권한 필요
Waiting for Accessibility permission|En attente de l’autorisation d’accessibilité|Warten auf Bedienungshilfen-Berechtigung|アクセシビリティ権限を待機中|손쉬운 사용 권한 대기 중
Open System Settings|Ouvrir Réglages Système|Systemeinstellungen öffnen|システム設定を開く|시스템 설정 열기
Open privacy settings|Ouvrir les réglages de confidentialité|Datenschutzeinstellungen öffnen|プライバシー設定を開く|개인정보 보호 설정 열기
Bluetooth|Bluetooth|Bluetooth|Bluetooth|Bluetooth
Bluetooth is on|Bluetooth est activé|Bluetooth ist eingeschaltet|Bluetooth はオンです|Bluetooth 켜짐
Bluetooth is off|Bluetooth est désactivé|Bluetooth ist ausgeschaltet|Bluetooth はオフです|Bluetooth 꺼짐
Connected|Connecté|Verbunden|接続済み|연결됨
Disconnected|Déconnecté|Getrennt|未接続|연결 끊김
Connect|Connecter|Verbinden|接続|연결
Disconnect|Déconnecter|Trennen|接続を解除|연결 해제
Other devices (%@)|Autres appareils (%@)|Andere Geräte (%@)|その他のデバイス（%@）|기타 기기(%@)
Left|Gauche|Links|左|왼쪽
Right|Droite|Rechts|右|오른쪽
Case|Boîtier|Case|ケース|케이스
Unknown device|Appareil inconnu|Unbekanntes Gerät|不明なデバイス|알 수 없는 기기
Signal|Signal|Signal|信号|신호
Channel|Canal|Kanal|チャンネル|채널
Transmit rate|Débit de transmission|Übertragungsrate|送信速度|전송 속도
Security|Sécurité|Sicherheit|セキュリティ|보안
Unsecured|Non sécurisé|Ungesichert|暗号化なし|보안 없음
Input source|Source de saisie|Eingabequelle|入力ソース|입력 소스
CPU & GPU|CPU et GPU|CPU und GPU|CPU と GPU|CPU 및 GPU
GPU memory|Mémoire du GPU|GPU-Speicher|GPU メモリ|GPU 메모리
Memory|Mémoire|Arbeitsspeicher|メモリ|메모리
App memory|Mémoire des apps|App-Speicher|アプリメモリ|앱 메모리
Wired memory|Mémoire résidente|Reservierter Speicher|確保されているメモリ|와이어드 메모리
Compressed|Compressée|Komprimiert|圧縮済み|압축됨
Swap used|Espace d’échange utilisé|Verwendeter Swap|使用中のスワップ|사용한 스왑
Page-ins|Entrées de pages|Page-ins|ページイン|페이지 인
Page-outs|Sorties de pages|Page-outs|ページアウト|페이지 아웃
Pressure|Pression|Speicherdruck|メモリプレッシャー|메모리 압력
Performance cores|Cœurs de performance|Performance-Kerne|高性能コア|성능 코어
Efficiency cores|Cœurs à haute efficacité|Effizienz-Kerne|高効率コア|효율 코어
Neural Engine|Neural Engine|Neural Engine|Neural Engine|Neural Engine
Load average|Charge moyenne|Durchschnittslast|平均負荷|평균 부하
Processes|Processus|Prozesse|プロセス|프로세스
Disks|Disques|Laufwerke|ディスク|디스크
Capacity|Capacité|Kapazität|容量|용량
Available|Disponible|Verfügbar|空き容量|사용 가능
Read|Lecture|Lesen|読み込み|읽기
Write|Écriture|Schreiben|書き込み|쓰기
Network|Réseau|Netzwerk|ネットワーク|네트워크
Network activity|Activité réseau|Netzwerkaktivität|ネットワークの活動|네트워크 활동
Speed history|Historique des débits|Verlauf der Übertragungsraten|通信速度の履歴|전송 속도 기록
Open speed history|Afficher l’historique des débits|Verlauf der Übertragungsraten öffnen|通信速度の履歴を開く|전송 속도 기록 열기
Back to network|Retour au réseau|Zurück zum Netzwerk|ネットワークに戻る|네트워크로 돌아가기
No sample in this interval|Aucune mesure sur cet intervalle|Kein Messwert in diesem Zeitraum|この時間帯の測定値なし|이 구간에 측정값 없음
BSD name|Nom BSD|BSD-Name|BSD名|BSD 이름
MAC address|Adresse MAC|MAC-Adresse|MACアドレス|MAC 주소
Noise|Bruit|Rauschen|ノイズ|잡음
IP address|Adresse IP|IP-Adresse|IPアドレス|IP 주소
Subnet mask|Masque de sous-réseau|Subnetzmaske|サブネットマスク|서브넷 마스크
Sampling…|Mesure en cours…|Messung läuft…|測定中…|측정 중…
No visible process activity|Aucune activité de processus visible|Keine sichtbare Prozessaktivität|確認できるプロセスの活動なし|표시할 프로세스 활동 없음
Process statistics unavailable|Statistiques des processus indisponibles|Prozessstatistiken nicht verfügbar|プロセスの統計を取得できません|프로세스 통계를 가져올 수 없음
Network speed|Débit réseau|Netzwerkgeschwindigkeit|ネットワーク速度|네트워크 속도
Interfaces|Interfaces|Schnittstellen|インターフェイス|인터페이스
Upload|Envoi|Upload|アップロード|업로드
Download|Réception|Download|ダウンロード|다운로드
Uploaded|Envoyé|Hochgeladen|送信済み|업로드됨
Downloaded|Reçu|Heruntergeladen|受信済み|다운로드됨
IPv6 only|IPv6 uniquement|Nur IPv6|IPv6 のみ|IPv6 전용
Router|Routeur|Router|ルーター|라우터
Sensors|Capteurs|Sensoren|センサー|센서
Temperature|Température|Temperatur|温度|온도
Power|Puissance|Leistung|電力|전력
Mainboard|Carte mère|Hauptplatine|ロジックボード|메인보드
Fan|Ventilateur|Lüfter|ファン|팬
Battery|Batterie|Batterie|バッテリー|배터리
Battery health|État de la batterie|Batteriezustand|バッテリーの状態|배터리 성능 상태
Cycle count|Nombre de cycles|Ladezyklen|充放電回数|사이클 수
Charge|Charge|Ladestand|充電率|충전량
Charged|Chargée|Aufgeladen|充電済み|충전 완료
Charging|En charge|Wird geladen|充電中|충전 중
On battery|Sur batterie|Im Batteriebetrieb|バッテリー駆動中|배터리 사용 중
Plugged in|Sur secteur|Am Stromnetz|電源アダプタ接続中|전원 연결됨
Low Power Mode|Mode économie d’énergie|Stromsparmodus|低電力モード|저전력 모드
No battery|Aucune batterie|Keine Batterie|バッテリーなし|배터리 없음
Power flow|Flux d’énergie|Energiefluss|電力の流れ|전력 흐름
Battery output|Puissance fournie par la batterie|Batterieabgabe|バッテリー出力|배터리 출력
Charging battery|Charge de la batterie|Batterie wird geladen|バッテリーに充電|배터리 충전
System power|Consommation du système|Systemleistung|システム消費電力|시스템 전력 소비
Adapter input|Entrée de l’adaptateur|Adaptereingang|アダプタ入力|어댑터 입력
Adapter rating|Puissance nominale de l’adaptateur|Adapter-Nennleistung|アダプタ定格|어댑터 정격
Voltage|Tension|Spannung|電圧|전압
Usage|Utilisation|Auslastung|使用率|사용량
Total|Total|Gesamt|合計|합계
System|Système|System|システム|시스템
User|Utilisateur|Benutzer|ユーザ|사용자
Idle|Inactif|Inaktiv|アイドル|유휴
Clipboard|Presse-papiers|Zwischenablage|クリップボード|클립보드
Clipboard sidebar|Volet du presse-papiers|Zwischenablage-Seitenleiste|クリップボードサイドバー|클립보드 사이드바
Hanging clipboard|Presse-papiers suspendu|Hängende Zwischenablage|吊り下げクリップボード|걸어 두는 클립보드
Search|Rechercher|Suchen|検索|검색
All|Tout|Alle|すべて|전체
Text|Texte|Text|テキスト|텍스트
Code|Code|Code|コード|코드
Links|Liens|Links|リンク|링크
Colors|Couleurs|Farben|カラー|색상
Images|Images|Bilder|画像|이미지
Files|Fichiers|Dateien|ファイル|파일
Source|Source|Quelle|コピー元|출처
All sources|Toutes les sources|Alle Quellen|すべてのコピー元|모든 출처
Filter by source app|Filtrer par app source|Nach Quell-App filtern|コピー元のアプリで絞り込む|원본 앱으로 필터링
Copy|Copier|Kopieren|コピー|복사
Paste|Coller|Einfügen|ペースト|붙여넣기
Pin|Épingler|Anheften|固定|고정
Unpin|Désépingler|Lösen|固定を解除|고정 해제
Delete|Supprimer|Löschen|削除|삭제
Remove|Retirer|Entfernen|取り除く|제거
Preview|Aperçu|Vorschau|プレビュー|미리보기
Time|Heure|Zeit|時刻|시간
Size|Taille|Größe|サイズ|크기
History shortcut|Raccourci de l’historique|Kurzbefehl für den Verlauf|履歴のショートカット|기록 단축키
History limit|Limite de l’historique|Verlaufslimit|履歴の上限|기록 한도
Retention|Durée de conservation|Aufbewahrungsdauer|保存期間|보관 기간
Pause capture|Suspendre l’enregistrement|Aufzeichnung pausieren|記録を一時停止|기록 일시 정지
Resume capture|Reprendre l’enregistrement|Aufzeichnung fortsetzen|記録を再開|기록 재개
Clear all|Tout effacer|Alles löschen|すべて消去|모두 지우기
Clear history…|Effacer l’historique…|Verlauf löschen …|履歴を消去…|기록 지우기…
Clear clipboard history?|Effacer l’historique du presse-papiers ?|Zwischenablageverlauf löschen?|クリップボードの履歴を消去しますか？|클립보드 기록을 지울까요?
Clear unpinned items|Effacer les éléments non épinglés|Nicht angeheftete Einträge löschen|固定していない項目を消去|고정하지 않은 항목 지우기
No matching items.|Aucun élément correspondant.|Keine passenden Einträge.|一致する項目がありません。|일치하는 항목이 없습니다.
No item selected|Aucun élément sélectionné|Kein Eintrag ausgewählt|項目が選択されていません|선택된 항목 없음
No history yet. Copy something to get started.|Aucun historique. Copiez un élément pour commencer.|Noch kein Verlauf. Kopiere etwas, um zu beginnen.|履歴はまだありません。何かコピーしてみましょう。|기록이 아직 없습니다. 항목을 복사해 보세요.
↑↓ Select|↑↓ Sélectionner|↑↓ Auswählen|↑↓ 選択|↑↓ 선택
↩ Paste|↩ Coller|↩ Einfügen|↩ ペースト|↩ 붙여넣기
↩ Copy|↩ Copier|↩ Kopieren|↩ コピー|↩ 복사
Just now|À l’instant|Gerade eben|たった今|방금 전
Yesterday|Hier|Gestern|昨日|어제
7 days|7 jours|7 Tage|7 日|7일
30 days|30 jours|30 Tage|30 日|30일
90 days|90 jours|90 Tage|90 日|90일
One year|Un an|Ein Jahr|1 年|1년
Forever|Indéfiniment|Unbegrenzt|無期限|영구 보관
200 items|200 éléments|200 Einträge|200 件|200개
1,000 items|1 000 éléments|1.000 Einträge|1,000 件|1,000개
5,000 items|5 000 éléments|5.000 Einträge|5,000 件|5,000개
Show line|Afficher la corde|Leine anzeigen|ロープを表示|줄 표시
Show / hide|Afficher / masquer|Ein- / ausblenden|表示／非表示|표시 / 가리기
Hang copied images|Suspendre les images copiées|Kopierte Bilder aufhängen|コピーした画像を吊るす|복사한 이미지 걸기
Reveal at the menu bar|Afficher au survol de la barre des menus|Beim Zeigen auf die Menüleiste einblenden|メニューバーにポインタを置くと表示|메뉴 막대에 포인터를 올리면 표시
Reveal new screenshots briefly|Afficher brièvement les nouvelles captures|Neue Bildschirmfotos kurz einblenden|新しいスクリーンショットを一時表示|새 스크린샷 잠시 표시
Mos settings|Réglages de Mos|Mos-Einstellungen|Mos 設定|Mos 설정
Mos smooth scrolling|Défilement fluide de Mos|Weiches Scrollen mit Mos|Mos スムーズスクロール|Mos 부드러운 스크롤
Basic|Général|Allgemein|基本|기본
Advanced|Avancé|Erweitert|詳細|고급
Exceptions|Exceptions|Ausnahmen|例外|예외
About|À propos|Über|情報|정보
Smooth scrolling|Défilement fluide|Weiches Scrollen|スムーズスクロール|부드러운 스크롤
Smooth|Fluide|Weich|スムーズ|부드럽게
Reverse|Inverser|Umkehren|反転|반전
Reverse direction|Inverser le sens|Richtung umkehren|方向を反転|방향 반전
Horizontal|Horizontal|Horizontal|水平|가로
Vertical|Vertical|Vertikal|垂直|세로
Boost key|Touche d’accélération|Beschleunigungstaste|加速キー|가속 키
Horizontal scroll key|Touche de défilement horizontal|Taste für horizontales Scrollen|横スクロールキー|가로 스크롤 키
Bypass key|Touche de suspension|Aussetztaste|一時停止キー|일시 정지 키
Minimum step|Pas minimal|Mindestschritt|最小ステップ|최소 이동 거리
Speed gain|Gain de vitesse|Geschwindigkeitsfaktor|速度倍率|속도 배율
Duration|Durée|Dauer|持続時間|지속 시간
Restore defaults|Rétablir les valeurs par défaut|Standardeinstellungen wiederherstellen|デフォルトに戻す|기본값 복원
Add application|Ajouter une application|App hinzufügen|アプリを追加|앱 추가
Add a running app…|Ajouter une app en cours…|Laufende App hinzufügen …|起動中のアプリを追加…|실행 중인 앱 추가…
Running applications|Applications ouvertes|Laufende Apps|起動中のアプリ|실행 중인 앱
Choose an app in Finder…|Choisir une app dans le Finder…|App im Finder auswählen …|Finder からアプリを選択…|Finder에서 앱 선택…
Edit app settings|Modifier les réglages de l’app|App-Einstellungen bearbeiten|アプリの設定を編集|앱 설정 편집
Remove app|Retirer l’app|App entfernen|アプリを取り除く|앱 제거
Application|Application|App|アプリ|앱
Allowlist mode|Liste d’autorisation|Positivliste|許可リストモード|허용 목록 모드
Hide Mos menu bar icon|Masquer l’icône Mos de la barre des menus|Mos-Symbol in der Menüleiste ausblenden|Mos のメニューバーアイコンを非表示|Mos 메뉴 막대 아이콘 가리기
Receiving mouse wheel events|Réception des événements de la molette|Mausradereignisse werden empfangen|マウスホイール入力を受信中|마우스 휠 이벤트 수신 중
Mos open source project|Projet open source Mos|Open-Source-Projekt Mos|Mos オープンソースプロジェクト|Mos 오픈 소스 프로젝트
No apps added yet.|Aucune application ajoutée.|Noch keine Apps hinzugefügt.|アプリはまだ追加されていません。|추가된 앱이 없습니다.
Notch panel|Panneau de l’encoche|Notch-Panel|ノッチパネル|노치 패널
Open notch panel|Ouvrir le panneau de l’encoche|Notch-Panel öffnen|ノッチパネルを開く|노치 패널 열기
Open CodeIsland|Ouvrir CodeIsland|CodeIsland öffnen|CodeIsland を開く|CodeIsland 열기
Show CodeIsland notch panel|Afficher le panneau de CodeIsland|CodeIsland-Notch-Panel anzeigen|CodeIsland のノッチパネルを表示|CodeIsland 노치 패널 표시
Receive local CodeIsland hooks|Recevoir les hooks locaux de CodeIsland|Lokale CodeIsland-Hooks empfangen|ローカルの CodeIsland フックを受信|로컬 CodeIsland 훅 수신
Listening for configured local hooks.|Écoute des hooks locaux configurés.|Konfigurierte lokale Hooks werden empfangen.|設定済みのローカルフックを待機中。|설정된 로컬 훅 수신 대기 중입니다.
Unknown|Inconnu|Unbekannt|不明|알 수 없음
Unknown error|Erreur inconnue|Unbekannter Fehler|不明なエラー|알 수 없는 오류
Unavailable|Indisponible|Nicht verfügbar|利用不可|사용할 수 없음
Not set|Non défini|Nicht festgelegt|未設定|설정되지 않음
None|Aucun|Keine|なし|없음
Yes|Oui|Ja|はい|예
No|Non|Nein|いいえ|아니요
On|Activé|Ein|オン|켬
Off|Désactivé|Aus|オフ|끔
Stopped|Arrêté|Gestoppt|停止|정지됨
Close|Fermer|Schließen|閉じる|닫기
Cancel|Annuler|Abbrechen|キャンセル|취소
Done|Terminé|Fertig|完了|완료
OK|OK|OK|OK|확인
Dismiss|Fermer|Schließen|閉じる|닫기
Loading…|Chargement…|Wird geladen …|読み込み中…|불러오는 중…
Standard|Standard|Standard|標準|표준
Select|Sélectionner|Auswählen|選択|선택
Notes|Notes|Notizen|メモ|메모
End|Terminer|Beenden|終了|종료
A plugin with this ID already exists|Un module possède déjà cet identifiant.|Ein Plug-in mit dieser ID ist bereits vorhanden.|この ID のプラグインは既に存在します。|이 ID의 플러그인이 이미 있습니다.
Adjust the external display under the pointer, or the first external display when the pointer is on the built-in screen. Turn this off to always follow the pointer.|Règle l’écran externe sous le pointeur, ou le premier écran externe si le pointeur est sur l’écran intégré. Désactivez cette option pour toujours suivre le pointeur.|Regelt das externe Display unter dem Zeiger oder das erste externe Display, wenn der Zeiger auf dem integrierten Bildschirm liegt. Deaktivieren, um immer dem Zeiger zu folgen.|ポインタの下の外部ディスプレイを調整します。ポインタが内蔵画面上にある場合は最初の外部ディスプレイを調整します。オフにすると常にポインタに従います。|포인터 아래의 외장 디스플레이를 조절합니다. 포인터가 내장 화면에 있으면 첫 번째 외장 디스플레이를 조절합니다. 이 옵션을 끄면 항상 포인터를 따릅니다.
All plugins are off. Open settings to enable one.|Tous les modules sont désactivés. Ouvrez les réglages pour en activer un.|Alle Plug-ins sind deaktiviert. Öffne die Einstellungen, um eines zu aktivieren.|すべてのプラグインがオフです。設定から有効にしてください。|모든 플러그인이 꺼져 있습니다. 설정에서 플러그인을 활성화하세요.
Allow Location to show network name|Autoriser la localisation pour afficher le nom du réseau|Ortungsdienste für den Netzwerknamen erlauben|ネットワーク名を表示するため位置情報を許可|네트워크 이름을 표시하려면 위치 접근 허용
Allow system audio capture in the macOS prompt.|Autorisez la capture de l’audio système dans la fenêtre macOS.|Erlaube die Aufnahme von Systemaudio im macOS-Dialog.|macOS のダイアログでシステムオーディオの収録を許可してください。|macOS 메시지에서 시스템 오디오 캡처를 허용하세요.
Allow system audio capture to adjust this device. Audio is never recorded or saved.|Autorisez la capture de l’audio système pour régler cet appareil. Le son n’est ni enregistré ni sauvegardé.|Erlaube den Zugriff auf Systemaudio, um dieses Gerät zu regeln. Audio wird weder aufgezeichnet noch gespeichert.|この機器の音量を調整するにはシステムオーディオへのアクセスを許可してください。音声の録音や保存は行いません。|이 기기를 조절하려면 시스템 오디오 접근을 허용하세요. 오디오는 녹음하거나 저장하지 않습니다.
Always use the selected appearance.|Toujours utiliser l’apparence sélectionnée.|Immer die gewählte Darstellung verwenden.|選択した外観を常に使用します。|선택한 모양을 항상 사용합니다.
Another app is using the backup shortcuts.|Une autre app utilise les raccourcis de secours.|Eine andere App verwendet die alternativen Kurzbefehle.|別のアプリが予備のショートカットを使用しています。|다른 앱이 대체 단축키를 사용 중입니다.
Automatic tries DDC first, then uses software volume if the display does not respond.|Le mode automatique essaie d’abord DDC, puis le volume logiciel si l’écran ne répond pas.|Im Automatikmodus wird zuerst DDC versucht. Antwortet das Display nicht, wird die Software-Lautstärke verwendet.|自動モードはまず DDC を試し、応答がなければソフトウェア音量を使用します。|자동 모드는 먼저 DDC를 시도하고, 디스플레이가 응답하지 않으면 소프트웨어 음량을 사용합니다.
Available storage and live read/write rates.|Espace disponible et débits de lecture et d’écriture en direct.|Freier Speicherplatz und aktuelle Lese- und Schreibraten.|空き容量とリアルタイムの読み書き速度。|사용 가능한 저장 공간과 실시간 읽기 및 쓰기 속도입니다.
Based on MonitorControl (MIT) and Status Trio (Apache-2.0)|Basé sur MonitorControl (MIT) et Status Trio (Apache-2.0)|Basiert auf MonitorControl (MIT) und Status Trio (Apache-2.0)|MonitorControl（MIT）と Status Trio（Apache-2.0）に基づいています|MonitorControl(MIT) 및 Status Trio(Apache-2.0) 기반
Brightness adjusted through macOS.|Luminosité réglée par macOS.|Helligkeit wurde über macOS angepasst.|macOS で輝度を調整しました。|macOS를 통해 밝기를 조절했습니다.
Cannot read plugin.json|Impossible de lire plugin.json|plugin.json kann nicht gelesen werden|plugin.json を読み込めません|plugin.json을 읽을 수 없습니다
Changing Low Power Mode requires an administrator password.|Un mot de passe administrateur est requis pour modifier le mode économie d’énergie.|Zum Ändern des Stromsparmodus ist ein Administratorkennwort erforderlich.|低電力モードの切り替えには管理者パスワードが必要です。|저전력 모드를 변경하려면 관리자 암호가 필요합니다.
Charge, battery health, cycle count, power flow, and Low Power Mode.|Charge, état de la batterie, cycles, flux d’énergie et mode économie d’énergie.|Ladestand, Batteriezustand, Ladezyklen, Energiefluss und Stromsparmodus.|充電率、バッテリーの状態、充放電回数、電力の流れ、低電力モード。|충전량, 배터리 성능 상태, 사이클 수, 전력 흐름 및 저전력 모드입니다.
Check for and install Mos updates in MyStatus Plugin Updates.|Vérifiez et installez les mises à jour de Mos dans la rubrique dédiée de MyStatus.|Mos-Updates unter „Plug-in-Updates“ in MyStatus suchen und installieren.|MyStatus の「プラグインのアップデート」で Mos の更新を確認してインストールできます。|MyStatus의 플러그인 업데이트에서 Mos 업데이트를 확인하고 설치하세요.
Click to copy, hold to annotate, double-click to preview, and drag to share. Runs inside MyStatus.|Cliquez pour copier, maintenez pour annoter, double-cliquez pour prévisualiser et glissez pour partager. Intégré à MyStatus.|Klicken zum Kopieren, gedrückt halten zum Kommentieren, doppelklicken für die Vorschau und ziehen zum Teilen. Läuft in MyStatus.|クリックでコピー、長押しで注釈、ダブルクリックでプレビュー、ドラッグで共有。MyStatus 内で動作します。|클릭해 복사하고, 길게 눌러 주석을 달고, 두 번 클릭해 미리 보고, 드래그해 공유하세요. MyStatus 안에서 실행됩니다.
Click to copy, then press ⌘V to paste|Cliquez pour copier, puis appuyez sur ⌘V pour coller|Klicken zum Kopieren, dann ⌘V zum Einfügen|クリックしてコピーし、⌘V でペースト|클릭하여 복사한 후 ⌘V로 붙여넣기
CPU, GPU, drive and battery temperatures, fan speed, and system power. Fans are read-only.|Températures du CPU, du GPU, des disques et de la batterie, vitesse des ventilateurs et consommation du système. La vitesse des ventilateurs est en lecture seule.|Temperaturen von CPU, GPU, Laufwerk und Batterie, Lüfterdrehzahl und Systemleistung. Lüfterwerte werden nur angezeigt.|CPU、GPU、ドライブ、バッテリーの温度、ファンの回転数、システム電力。ファンの回転数は表示のみです。|CPU, GPU, 드라이브 및 배터리 온도, 팬 속도와 시스템 전력입니다. 팬 속도는 조회만 가능합니다.
Create audio device|Créer un périphérique audio|Audiogerät erstellen|オーディオデバイスを作成|오디오 기기 생성
Create audio tap|Créer une capture audio|Audioabgriff erstellen|オーディオタップを作成|오디오 탭 생성
DDC command sent; the display returned no reading.|Commande DDC envoyée. L’écran n’a renvoyé aucune mesure.|DDC-Befehl gesendet. Das Display hat keinen Messwert geliefert.|DDC コマンドを送信しました。ディスプレイから測定値の応答はありません。|DDC 명령을 전송했습니다. 디스플레이가 측정값을 반환하지 않았습니다.
Deleted history cannot be recovered.|L’historique effacé ne peut pas être récupéré.|Gelöschte Verläufe können nicht wiederhergestellt werden.|削除した履歴は復元できません。|삭제된 기록은 복구할 수 없습니다.
Disconnect this device? You may lose input control.|Déconnecter cet appareil ? Vous pourriez perdre l’accès à votre clavier ou votre souris.|Dieses Gerät trennen? Tastatur oder Maus könnten danach nicht mehr verfügbar sein.|このデバイスの接続を解除しますか？入力操作ができなくなる場合があります。|이 기기의 연결을 끊을까요? 입력 장치를 사용하지 못할 수 있습니다.
Drag the slider to enable software volume|Déplacez le curseur pour activer le volume logiciel|Regler bewegen, um die Software-Lautstärke zu aktivieren|スライダを動かしてソフトウェア音量を有効にする|슬라이더를 움직여 소프트웨어 음량 켜기
Drag to adjust. macOS requests system audio capture permission the first time. Audio is never recorded or saved.|Faites glisser pour régler le volume. macOS demande l’autorisation de capturer l’audio système la première fois. Le son n’est ni enregistré ni sauvegardé.|Zum Einstellen ziehen. macOS fragt beim ersten Mal nach Zugriff auf Systemaudio. Audio wird weder aufgezeichnet noch gespeichert.|ドラッグして調整します。初回は macOS がシステムオーディオの収録許可を求めます。音声の録音や保存は行いません。|드래그하여 조절하세요. 처음에는 macOS가 시스템 오디오 캡처 권한을 요청합니다. 오디오는 녹음하거나 저장하지 않습니다.
Enable Accessibility permission to activate key handling.|Autorisez l’accessibilité pour activer la gestion des touches.|Erlaube den Zugriff auf Bedienungshilfen, um die Tastensteuerung zu aktivieren.|キー操作を有効にするにはアクセシビリティ権限を許可してください。|키 기능을 사용하려면 손쉬운 사용 권한을 허용하세요.
Enable MyStatus in Accessibility to control displays with F1/F2 and F10–F12. Takes effect immediately.|Activez MyStatus dans Accessibilité pour contrôler les écrans avec F1/F2 et F10–F12. L’effet est immédiat.|Aktiviere MyStatus unter „Bedienungshilfen“, um Displays mit F1/F2 und F10–F12 zu steuern. Die Änderung gilt sofort.|アクセシビリティで MyStatus を許可すると、F1/F2 と F10〜F12 でディスプレイを操作できます。変更はすぐに適用されます。|손쉬운 사용에서 MyStatus를 허용하면 F1/F2와 F10~F12로 디스플레이를 제어할 수 있습니다. 변경은 즉시 적용됩니다.
External display brightness/contrast through DDC, native display brightness, and software dimming.|Luminosité et contraste des écrans externes par DDC, luminosité de l’écran intégré et atténuation logicielle.|Helligkeit und Kontrast externer Displays per DDC, Helligkeit des integrierten Displays und Software-Dimmung.|DDC による外部画面の輝度とコントラスト、内蔵画面の輝度調整、ソフトウェア減光。|DDC를 통한 외장 디스플레이 밝기와 대비, 내장 화면 밝기 및 소프트웨어 디밍입니다.
F1/F2 control external display brightness; F10–F12 control display volume. macOS handles built-in displays and ordinary speakers.|F1/F2 règlent la luminosité des écrans externes. F10–F12 règlent leur volume. macOS gère l’écran intégré et les haut-parleurs ordinaires.|F1/F2 regeln die Helligkeit externer Displays und F10–F12 deren Lautstärke. macOS steuert integrierte Displays und gewöhnliche Lautsprecher.|F1/F2 で外部画面の輝度、F10〜F12 で画面の音量を調整します。内蔵画面や通常のスピーカーは macOS が制御します。|F1/F2는 외장 디스플레이 밝기, F10~F12는 디스플레이 음량을 조절합니다. 내장 디스플레이와 일반 스피커는 macOS에서 제어합니다.
Fetch source and rebuild plugins on this Mac|Récupérer le code source et recompiler les modules sur ce Mac|Quellcode abrufen und Plug-ins auf diesem Mac neu erstellen|ソースを取得してこの Mac でプラグインを再ビルド|소스를 가져와 이 Mac에서 플러그인 다시 빌드
Follow macOS when it switches between Light and Dark Mode.|Suivre macOS lors du passage du mode clair au mode sombre.|Folgt macOS beim Wechsel zwischen heller und dunkler Darstellung.|ライトとダークの切り替えを macOS に合わせます。|macOS의 라이트 및 다크 모드 전환을 따릅니다.
For automatic history, allow MyStatus to paste from other apps in privacy settings.|Pour tenir un historique automatique, autorisez MyStatus à coller depuis d’autres apps dans les réglages de confidentialité.|Erlaube MyStatus in den Datenschutzeinstellungen das Einfügen aus anderen Apps, um den Verlauf automatisch zu führen.|履歴を自動で記録するには、プライバシー設定で MyStatus に他のアプリからのペーストを許可してください。|기록을 자동으로 저장하려면 개인정보 보호 설정에서 MyStatus가 다른 앱에서 붙여넣도록 허용하세요.
GitHub request failed or was rate limited. Try again later.|La requête GitHub a échoué ou la limite de requêtes a été atteinte. Réessayez plus tard.|Die GitHub-Anfrage ist fehlgeschlagen oder das Anfragelimit ist erreicht. Versuche es später erneut.|GitHub へのリクエストに失敗したか、利用制限に達しました。後でもう一度お試しください。|GitHub 요청에 실패했거나 요청 한도에 도달했습니다. 나중에 다시 시도하세요.
Hold to pause smoothing.|Maintenez pour suspendre le défilement fluide.|Gedrückt halten, um weiches Scrollen auszusetzen.|押している間はスムーズスクロールを一時停止します。|누르고 있는 동안 부드러운 스크롤을 일시 정지합니다.
Hold to scroll faster.|Maintenez pour défiler plus vite.|Gedrückt halten, um schneller zu scrollen.|押している間はスクロールが速くなります。|누르고 있는 동안 더 빠르게 스크롤합니다.
Hold to turn vertical scrolling into horizontal scrolling.|Maintenez pour transformer le défilement vertical en défilement horizontal.|Gedrückt halten, um vertikales in horizontales Scrollen umzuwandeln.|押している間は縦スクロールを横スクロールに切り替えます。|누르고 있는 동안 세로 스크롤을 가로 스크롤로 바꿉니다.
Hold ⌥⇧ for smaller adjustments.|Maintenez ⌥⇧ pour des réglages plus fins.|Halte ⌥⇧ für feinere Schritte gedrückt.|細かく調整するには ⌥⇧ を押したまま操作します。|더 작은 단위로 조절하려면 ⌥⇧를 누르세요.
Installed. Restart MyStatus to load it.|Installation terminée. Redémarrez MyStatus pour charger le module.|Installiert. Starte MyStatus neu, um das Plug-in zu laden.|インストールしました。読み込むには MyStatus を再起動してください。|설치했습니다. 적용하려면 MyStatus를 다시 실행하세요.
Library did not return a DeckPlugin|La bibliothèque n’a pas renvoyé de DeckPlugin|Die Bibliothek hat kein DeckPlugin zurückgegeben|ライブラリから DeckPlugin が返されませんでした|라이브러리가 DeckPlugin을 반환하지 않았습니다
Listed apps use their own settings. Other apps use the global settings.|Les apps de la liste utilisent leurs propres réglages. Les autres utilisent les réglages généraux.|Aufgeführte Apps verwenden eigene Einstellungen. Für andere Apps gelten die allgemeinen Einstellungen.|一覧のアプリには個別設定を、それ以外のアプリには全体設定を適用します。|목록의 앱에는 개별 설정을, 나머지 앱에는 공통 설정을 적용합니다.
Local hook listener unavailable. Check for an existing CodeIsland instance.|Impossible d’écouter les hooks locaux. Vérifiez si CodeIsland est déjà lancé.|Lokale Hooks können nicht empfangen werden. Prüfe, ob CodeIsland bereits läuft.|ローカルフックを受信できません。CodeIsland が既に起動していないか確認してください。|로컬 훅을 수신할 수 없습니다. CodeIsland가 이미 실행 중인지 확인하세요.
macOS denied clipboard access. Change permission in privacy settings to record new items.|macOS a refusé l’accès au presse-papiers. Modifiez l’autorisation dans les réglages de confidentialité pour enregistrer les nouveaux éléments.|macOS hat den Zugriff auf die Zwischenablage verweigert. Ändere die Berechtigung in den Datenschutzeinstellungen, um neue Einträge aufzuzeichnen.|macOS がクリップボードへのアクセスを拒否しました。新しい項目を記録するにはプライバシー設定で権限を変更してください。|macOS가 클립보드 접근을 거부했습니다. 새 항목을 기록하려면 개인정보 보호 설정에서 권한을 변경하세요.
macOS may request clipboard access. You can allow it in Privacy & Security.|macOS peut demander l’accès au presse-papiers. Vous pouvez l’autoriser dans Confidentialité et sécurité.|macOS kann den Zugriff auf die Zwischenablage anfordern. Er lässt sich unter „Datenschutz & Sicherheit“ erlauben.|macOS がクリップボードへのアクセスを求める場合があります。「プライバシーとセキュリティ」で許可できます。|macOS가 클립보드 접근을 요청할 수 있습니다. 개인정보 보호 및 보안에서 허용할 수 있습니다.
macOS rejected this brightness change.|macOS a refusé ce changement de luminosité.|macOS hat diese Helligkeitsänderung abgelehnt.|macOS が輝度変更を拒否しました。|macOS가 이 밝기 변경을 거부했습니다.
macOS requests Bluetooth permission when you first toggle Bluetooth or connect a device.|macOS demande l’autorisation Bluetooth la première fois que vous changez son état ou connectez un appareil.|macOS fragt beim ersten Ein- oder Ausschalten von Bluetooth oder beim ersten Verbinden eines Geräts nach der Bluetooth-Berechtigung.|Bluetooth の初回の切り替え時またはデバイスの接続時に、macOS が Bluetooth の使用許可を求めます。|Bluetooth를 처음 켜거나 끄거나 기기를 연결할 때 macOS가 Bluetooth 권한을 요청합니다.
macOS requires Location permission for Wi-Fi names. Requested only when you click; the app does not read your location.|macOS exige l’accès à la localisation pour afficher les noms Wi-Fi. La demande apparaît lorsque vous cliquez. Votre position n’est pas lue.|macOS verlangt für WLAN-Namen den Zugriff auf Ortungsdienste. Die Abfrage erscheint beim Klicken. Die App liest deinen Standort nicht aus.|Wi-Fi 名の表示には macOS の位置情報権限が必要です。クリックしたときだけ許可を求め、現在地は取得しません。|Wi-Fi 이름을 표시하려면 macOS 위치 권한이 필요합니다. 클릭할 때만 권한을 요청하며 현재 위치는 읽지 않습니다.
Master volume and input/output devices. Display audio supports DDC or software volume.|Volume général et périphériques d’entrée et de sortie. Le son de l’écran se règle via DDC ou le volume logiciel.|Hauptlautstärke und Ein-/Ausgabegeräte. Die Displaylautstärke lässt sich per DDC oder Software regeln.|主音量と入出力デバイス。ディスプレイ音量は DDC またはソフトウェアで調整できます。|주 음량과 입출력 기기를 제어합니다. 디스플레이 음량은 DDC 또는 소프트웨어로 조절할 수 있습니다.
Memory pressure, usage, paging, swap, and top memory consumers.|Pression et utilisation de la mémoire, pagination, espace d’échange et apps les plus gourmandes.|Speicherdruck, Speicherauslastung, Paging, Swap und Apps mit dem höchsten Speicherbedarf.|メモリプレッシャー、使用量、ページング、スワップ、メモリ使用量の多いアプリ。|메모리 압력, 사용량, 페이징, 스왑 및 메모리 사용량이 많은 앱입니다.
Native wxtsky/CodeIsland notch panel and session status|Panneau natif de l’encoche et état des sessions de wxtsky/CodeIsland|Natives Notch-Panel und Sitzungsstatus von wxtsky/CodeIsland|wxtsky/CodeIsland のネイティブノッチパネルとセッション状態|wxtsky/CodeIsland의 네이티브 노치 패널 및 세션 상태
No output device|Aucun périphérique de sortie|Kein Ausgabegerät|出力デバイスなし|출력 기기 없음
One icon shows battery, Wi-Fi, and volume. Scroll over it to adjust volume.|Une seule icône affiche la batterie, le Wi-Fi et le volume. Défilez sur l’icône pour régler le volume.|Ein Symbol zeigt Batterie, WLAN und Lautstärke. Über dem Symbol scrollen, um die Lautstärke anzupassen.|ひとつのアイコンにバッテリー、Wi-Fi、音量を表示します。アイコン上でスクロールすると音量を調整できます。|한 아이콘에 배터리, Wi-Fi, 음량을 표시합니다. 아이콘 위에서 스크롤하여 음량을 조절하세요.
Only listed apps use Mos settings.|Les réglages Mos s’appliquent uniquement aux apps de la liste.|Mos-Einstellungen gelten nur für Apps auf der Liste.|一覧にあるアプリだけに Mos の設定を適用します。|목록에 있는 앱에만 Mos 설정을 적용합니다.
Place .deckplugin folders in the plugins folder, then choose Rescan. New plugins start disabled.|Placez les dossiers .deckplugin dans le dossier des modules, puis relancez l’analyse. Les nouveaux modules sont désactivés par défaut.|Lege .deckplugin-Ordner im Plug-in-Ordner ab und wähle „Erneut suchen“. Neue Plug-ins sind zunächst deaktiviert.|.deckplugin フォルダをプラグインフォルダに入れ、「再スキャン」を選択してください。新しいプラグインは初期状態では無効です。|.deckplugin 폴더를 플러그인 폴더에 넣고 다시 검색하세요. 새 플러그인은 기본적으로 비활성화됩니다.
Please quit the previous version|Quittez la version précédente|Vorherige Version bitte beenden|以前のバージョンを終了してください|이전 버전을 종료하세요
Plugin 1 · Clipboard sidebar for text, links, colors, images, and files. Search, pin, and open with a shortcut. Stored only on this Mac.|Module 1 · Volet du presse-papiers pour le texte, les liens, les couleurs, les images et les fichiers. Recherche, épinglage et ouverture par raccourci. Les données restent sur ce Mac.|Plug-in 1 · Zwischenablage-Seitenleiste für Texte, Links, Farben, Bilder und Dateien. Suchen, anheften und per Kurzbefehl öffnen. Daten bleiben auf diesem Mac.|プラグイン 1 · テキスト、リンク、色、画像、ファイルを扱うクリップボードのサイドバー。検索、固定、ショートカットで開く操作に対応し、データはこの Mac だけに保存します。|플러그인 1 · 텍스트, 링크, 색상, 이미지, 파일을 위한 클립보드 사이드바입니다. 검색, 고정, 단축키 열기를 지원하며 데이터는 이 Mac에만 저장됩니다.
Plugin 2 · Hang screenshots and copied images across the top of the screen, with drag, preview, and annotation.|Module 2 · Suspendez les captures et les images copiées en haut de l’écran. Vous pouvez les déplacer, les prévisualiser et les annoter.|Plug-in 2 · Bildschirmfotos und kopierte Bilder am oberen Bildschirmrand aufhängen, ziehen, ansehen und kommentieren.|プラグイン 2 · スクリーンショットやコピーした画像を画面上部に吊るします。ドラッグ、プレビュー、注釈に対応します。|플러그인 2 · 스크린샷과 복사한 이미지를 화면 위에 걸고 드래그, 미리보기, 주석을 사용할 수 있습니다.
Plugin 2 · Hang screenshots and images|Module 2 · Suspendre les captures et les images|Plug-in 2 · Bildschirmfotos und Bilder aufhängen|プラグイン 2 · スクリーンショットと画像を吊るす|플러그인 2 · 스크린샷과 이미지 걸기
Plugin 3 · Smooth mouse-wheel scrolling, independent axis reversal, speed, inertia, and app exclusions.|Module 3 · Défilement fluide à la molette, inversion par axe, vitesse, inertie et exceptions par app.|Plug-in 3 · Weiches Scrollen per Mausrad, Umkehr je Achse, Geschwindigkeit, Trägheit und App-Ausnahmen.|プラグイン 3 · マウスホイールのスムーズスクロール、軸ごとの反転、速度、慣性、アプリ別の例外設定。|플러그인 3 · 부드러운 마우스 휠 스크롤, 축별 반전, 속도, 관성 및 앱별 예외 설정입니다.
Plugin 4 · Claude / Codex session monitoring and a floating island, powered by the original CodeIslandCore parser.|Module 4 · Surveillance des sessions Claude et Codex dans un panneau flottant, avec l’analyseur CodeIslandCore d’origine.|Plug-in 4 · Überwachung von Claude- und Codex-Sitzungen in einem schwebenden Panel mit dem ursprünglichen CodeIslandCore-Parser.|プラグイン 4 · 元の CodeIslandCore パーサーを使用して、Claude と Codex のセッションをフローティングパネルで監視します。|플러그인 4 · 원본 CodeIslandCore 파서를 사용해 Claude 및 Codex 세션을 플로팅 패널에서 모니터링합니다.
Plugin 4 · The native wxtsky/CodeIsland notch panel and session discovery.|Module 4 · Panneau natif de l’encoche et détection des sessions de wxtsky/CodeIsland.|Plug-in 4 · Natives Notch-Panel und Sitzungserkennung von wxtsky/CodeIsland.|プラグイン 4 · wxtsky/CodeIsland のネイティブノッチパネルとセッション検出。|플러그인 4 · wxtsky/CodeIsland의 네이티브 노치 패널 및 세션 감지입니다.
Plugin code runs inside MyStatus with its permissions, including clipboard history access. Enable only trusted sources.|Les modules s’exécutent dans MyStatus avec ses autorisations, dont l’accès à l’historique du presse-papiers. N’activez que les sources de confiance.|Plug-ins werden in MyStatus mit dessen Berechtigungen ausgeführt, einschließlich des Zugriffs auf den Zwischenablageverlauf. Aktiviere nur vertrauenswürdige Quellen.|プラグインは MyStatus 内で実行され、クリップボード履歴など同じ権限でアクセスできます。信頼できる配布元のものだけを有効にしてください。|플러그인은 MyStatus 안에서 실행되며 클립보드 기록 접근을 포함한 권한을 공유합니다. 신뢰할 수 있는 출처만 활성화하세요.
Plugin files changed after approval. Enable the plugin again to approve the new version.|Les fichiers du module ont changé depuis l’autorisation. Activez de nouveau le module pour approuver la nouvelle version.|Plug-in-Dateien wurden nach der Freigabe geändert. Aktiviere das Plug-in erneut, um die neue Version freizugeben.|許可後にプラグインのファイルが変更されました。新しいバージョンを承認するには再度有効にしてください。|승인 후 플러그인 파일이 변경되었습니다. 새 버전을 승인하려면 플러그인을 다시 활성화하세요.
Plugin library not found|Bibliothèque du module introuvable|Plug-in-Bibliothek nicht gefunden|プラグインライブラリが見つかりません|플러그인 라이브러리를 찾을 수 없습니다
Press a shortcut…|Appuyez sur un raccourci…|Kurzbefehl drücken …|ショートカットを押してください…|단축키를 누르세요…
Processor usage, core load, frequency, power, and top CPU consumers.|Utilisation du processeur, charge par cœur, fréquence, consommation et apps les plus gourmandes en CPU.|Prozessorauslastung, Last pro Kern, Frequenz, Leistung und Apps mit der höchsten CPU-Nutzung.|プロセッサの使用率、コアごとの負荷、周波数、電力、CPU 使用率の高いアプリ。|프로세서 사용량, 코어별 부하, 주파수, 전력 및 CPU 사용량이 많은 앱입니다.
Reads copied images and watches screenshot folders only while enabled.|Lit les images copiées et surveille les dossiers de captures uniquement lorsqu’il est activé.|Liest kopierte Bilder und überwacht Bildschirmfoto-Ordner nur, wenn das Plug-in aktiviert ist.|有効なときだけコピーした画像を読み取り、スクリーンショットフォルダを監視します。|활성화한 동안에만 복사한 이미지를 읽고 스크린샷 폴더를 감시합니다.
Reads local AI session logs. Receiving configured local CodeIsland hooks is optional.|Lit les journaux locaux des sessions IA. La réception des hooks locaux CodeIsland déjà configurés est facultative.|Liest lokale KI-Sitzungsprotokolle. Der Empfang konfigurierter lokaler CodeIsland-Hooks ist optional.|ローカルの AI セッションログを読み取ります。設定済みのローカル CodeIsland フックの受信は任意です。|로컬 AI 세션 로그를 읽습니다. 설정된 로컬 CodeIsland 훅 수신은 선택 사항입니다.
Reads local Claude / Codex transcripts only while enabled. No remote devices or push notifications.|Lit les transcriptions locales de Claude et Codex uniquement lorsque le module est activé. Aucun appareil distant ni notification push.|Liest lokale Claude- und Codex-Protokolle nur bei Aktivierung. Ohne entfernte Geräte oder Push-Mitteilungen.|有効なときだけ Claude と Codex のローカル会話ログを読み取ります。リモート端末やプッシュ通知は使用しません。|활성화한 동안에만 로컬 Claude 및 Codex 대화 기록을 읽습니다. 원격 기기나 푸시 알림은 사용하지 않습니다.
Register audio callback|Enregistrer la fonction de rappel audio|Audio-Callback registrieren|オーディオコールバックを登録|오디오 콜백 등록
Requires Accessibility permission for mouse-wheel events; trackpad gestures remain unchanged.|L’autorisation d’accessibilité est requise pour la molette. Les gestes du trackpad sont préservés.|Für Mausradereignisse ist die Berechtigung für Bedienungshilfen erforderlich. Trackpad-Gesten bleiben unverändert.|マウスホイールの操作にはアクセシビリティ権限が必要です。トラックパッドのジェスチャは変わりません。|마우스 휠 이벤트에는 손쉬운 사용 권한이 필요합니다. 트랙패드 제스처는 그대로 유지됩니다.
Requires Accessibility permission. Disable MonitorControl key handling to avoid duplicate adjustments.|L’autorisation d’accessibilité est requise. Désactivez la gestion des touches dans MonitorControl pour éviter les doubles réglages.|Die Berechtigung für Bedienungshilfen ist erforderlich. Deaktiviere die Tastensteuerung von MonitorControl, um doppelte Anpassungen zu vermeiden.|アクセシビリティ権限が必要です。二重調整を防ぐには MonitorControl 側のキー操作を無効にしてください。|손쉬운 사용 권한이 필요합니다. 두 번 조절되지 않도록 MonitorControl의 키 기능을 끄세요.
Requires macOS 14.2 or later|Nécessite macOS 14.2 ou une version ultérieure|Erfordert macOS 14.2 oder neuer|macOS 14.2 以降が必要です|macOS 14.2 이상 필요
Requires Xcode Command Line Tools. Failed builds preserve existing plugins; incompatible upstream changes appear here. All extensions run inside MyStatus without installing standalone apps.|Nécessite les outils en ligne de commande Xcode. En cas d’échec de la compilation, le module actuel est conservé. Les changements incompatibles sont signalés ici. Les extensions s’exécutent dans MyStatus.|Erfordert die Xcode Command Line Tools. Bei fehlgeschlagenen Builds bleibt das vorhandene Plug-in erhalten. Inkompatible Änderungen werden hier angezeigt. Erweiterungen laufen direkt in MyStatus.|Xcode Command Line Tools が必要です。ビルドに失敗しても現在のプラグインは保持され、互換性のない変更はここに表示されます。すべての拡張機能は MyStatus 内で動作します。|Xcode Command Line Tools가 필요합니다. 빌드에 실패하면 기존 플러그인을 유지하며 호환되지 않는 변경 사항은 여기에 표시됩니다. 확장 프로그램은 모두 MyStatus 안에서 실행됩니다.
Resolve process audio object|Identifier l’objet audio du processus|Audioobjekt des Prozesses ermitteln|プロセスのオーディオオブジェクトを特定|프로세스 오디오 객체 확인
Set 0% for solid cards and 100% for more translucent cards. Light intensity adjusts highlights. Reduce Transparency uses solid cards.|À 0 %, les cartes sont opaques. À 100 %, les cartes sont plus transparentes. L’intensité lumineuse règle les reflets. L’option Réduire la transparence rend les cartes opaques.|Bei 0 % sind Karten deckend, bei 100 % sind sie durchscheinender. Die Lichtintensität regelt die Glanzlichter. „Transparenz reduzieren“ verwendet deckende Karten.|0% では不透明、100% では背景がより透明になります。光の強さでハイライトを調整できます。「透明度を下げる」が有効な場合は不透明になります。|0%에서는 불투명, 100%에서는 카드가 더 투명해집니다. 빛 강도는 밝은 부분을 조절합니다. 투명도 줄이기를 켜면 불투명 카드로 표시됩니다.
Show network speed, CPU, and memory usage in the menu bar.|Afficher le débit réseau et l’utilisation du CPU et de la mémoire dans la barre des menus.|Netzwerkgeschwindigkeit, CPU- und Speicherauslastung in der Menüleiste anzeigen.|メニューバーにネットワーク速度、CPU 使用率、メモリ使用量を表示します。|메뉴 막대에 네트워크 속도, CPU 및 메모리 사용량을 표시합니다.
Skips confidential clipboard contents and blocked apps.|Ignore les éléments confidentiels et les apps bloquées.|Überspringt vertrauliche Zwischenablageinhalte und blockierte Apps.|機密としてマークされた内容や除外したアプリは記録しません。|기밀로 표시된 클립보드 콘텐츠와 차단된 앱은 건너뜁니다.
Software volume requires system audio capture permission. Audio is adjusted and played immediately, never recorded or saved.|Le volume logiciel requiert l’autorisation de capturer l’audio système. Le son est réglé puis lu immédiatement, sans être enregistré ni sauvegardé.|Die Software-Lautstärke benötigt Zugriff auf Systemaudio. Audio wird angepasst und sofort wiedergegeben, ohne Aufzeichnung oder Speicherung.|ソフトウェア音量にはシステムオーディオへのアクセスが必要です。音声は調整後すぐに再生され、録音や保存は行いません。|소프트웨어 음량을 사용하려면 시스템 오디오 캡처 권한이 필요합니다. 오디오는 조절한 후 즉시 재생하며 녹음하거나 저장하지 않습니다.
Source exceeds the adapter's size limit.|Le code source dépasse la taille maximale de l’adaptateur.|Der Quellcode überschreitet die Größenbeschränkung des Adapters.|ソースがアダプタのサイズ制限を超えています。|소스가 어댑터의 크기 제한을 초과합니다.
Start audio|Démarrer l’audio|Audio starten|オーディオを開始|오디오 시작
Start MyStatus at login and load Mos when it is enabled.|Ouvrir MyStatus à la connexion et charger Mos s’il est activé.|MyStatus bei der Anmeldung öffnen und Mos laden, wenn es aktiviert ist.|ログイン時に MyStatus を起動し、有効な場合は Mos を読み込みます。|로그인 시 MyStatus를 실행하고 Mos가 활성화된 경우 불러옵니다.
Switch enabled input sources from the panel.|Changer de source de saisie active depuis le panneau.|Aktivierte Eingabequellen im Panel wechseln.|パネルから有効な入力ソースを切り替えます。|패널에서 활성화된 입력 소스를 전환합니다.
Switch networks in System Settings|Changer de réseau dans Réglages Système|Netzwerk in den Systemeinstellungen wechseln|システム設定でネットワークを切り替える|시스템 설정에서 네트워크 전환
The display confirmed the brightness level.|L’écran a confirmé le niveau de luminosité.|Das Display hat die Helligkeitsstufe bestätigt.|ディスプレイが輝度レベルを確認しました。|디스플레이가 밝기 수준을 확인했습니다.
The display did not respond to DDC; using software dimming.|L’écran n’a pas répondu à DDC. Atténuation logicielle activée.|Das Display antwortet nicht auf DDC. Software-Dimmung ist aktiv.|ディスプレイが DDC に応答しなかったため、ソフトウェア減光に切り替えました。|디스플레이가 DDC에 응답하지 않아 소프트웨어 디밍을 사용합니다.
The previous version is still running. Quit StatusDeck or the older MyStatus, then open this version again.|La version précédente est encore ouverte. Quittez StatusDeck ou l’ancienne version de MyStatus, puis rouvrez cette version.|Die vorherige Version läuft noch. Beende StatusDeck oder das ältere MyStatus und öffne dann diese Version erneut.|以前のバージョンが実行中です。StatusDeck または古い MyStatus を終了してから、このバージョンを開き直してください。|이전 버전이 아직 실행 중입니다. StatusDeck 또는 이전 MyStatus를 종료한 후 이 버전을 다시 열어 주세요.
The upstream structure or plugin API changed. This adapter needs an update.|La structure du projet source ou l’API des modules a changé. L’adaptateur doit être mis à jour.|Die Upstream-Struktur oder Plug-in-API hat sich geändert. Der Adapter muss aktualisiert werden.|上流プロジェクトの構造またはプラグイン API が変更されました。アダプタの更新が必要です。|원본 프로젝트 구조 또는 플러그인 API가 변경되었습니다. 어댑터를 업데이트해야 합니다.
This display does not report its brightness. The last requested value is shown.|Cet écran ne communique pas sa luminosité. La dernière valeur demandée est affichée.|Dieses Display meldet keine Helligkeit. Angezeigt wird der zuletzt angeforderte Wert.|このディスプレイから輝度を読み取れないため、最後に指定した値を表示します。|이 디스플레이는 밝기 값을 반환하지 않습니다. 마지막으로 요청한 값을 표시합니다.
This display ignores DDC volume commands. Software volume is used instead.|Cet écran ne répond pas aux commandes de volume DDC. Le volume logiciel est utilisé.|Dieses Display reagiert nicht auf DDC-Lautstärkebefehle. Die Software-Lautstärke wird verwendet.|このディスプレイは DDC の音量コマンドに応答しないため、ソフトウェア音量を使用します。|이 디스플레이가 DDC 음량 명령에 응답하지 않아 소프트웨어 음량을 사용합니다.
This shortcut is already used by another app.|Ce raccourci est déjà utilisé par une autre app.|Dieser Kurzbefehl wird bereits von einer anderen App verwendet.|このショートカットは別のアプリで使用されています。|다른 앱이 이미 이 단축키를 사용 중입니다.
Toggle Bluetooth, manage paired devices, and view battery levels.|Activer ou désactiver le Bluetooth, gérer les appareils jumelés et consulter leur batterie.|Bluetooth umschalten, gekoppelte Geräte verwalten und Ladestände anzeigen.|Bluetooth のオン・オフ、ペアリング済みデバイスの管理、バッテリー残量の表示。|Bluetooth 전환, 페어링된 기기 관리 및 배터리 잔량 확인입니다.
Toggle Wi-Fi and view signal, channel, rate, and security. Switch networks in System Settings.|Activez ou désactivez le Wi-Fi et consultez le signal, le canal, le débit et la sécurité. Changez de réseau dans Réglages Système.|WLAN ein- oder ausschalten und Signal, Kanal, Rate und Sicherheit anzeigen. Der Netzwerkwechsel erfolgt in den Systemeinstellungen.|Wi-Fi の切り替えと信号、チャンネル、速度、セキュリティの表示。ネットワークの切り替えはシステム設定で行います。|Wi-Fi를 켜거나 끄고 신호, 채널, 속도, 보안을 확인합니다. 네트워크는 시스템 설정에서 전환하세요.
Turn off Bluetooth? Your keyboard or mouse may disconnect.|Désactiver le Bluetooth ? Le clavier ou la souris peut se déconnecter.|Bluetooth ausschalten? Tastatur oder Maus könnten getrennt werden.|Bluetooth をオフにしますか？キーボードやマウスの接続が解除される場合があります。|Bluetooth를 끌까요? 키보드나 마우스의 연결이 끊길 수 있습니다.
UI preview · controls disabled|Aperçu de l’interface · Commandes désactivées|Oberflächenvorschau · Bedienelemente deaktiviert|UI プレビュー · コントロール無効|UI 미리보기 · 제어 기능 비활성화
Unchanged (canceled or permission denied)|Inchangé (opération annulée ou autorisation refusée)|Unverändert (abgebrochen oder Zugriff verweigert)|変更なし（キャンセルまたは権限が拒否されました）|변경 없음(취소했거나 권한 거부됨)
Update not installed. The current version is unchanged.|Mise à jour non installée. La version actuelle est conservée.|Update nicht installiert. Die aktuelle Version bleibt erhalten.|アップデートをインストールできなかったため、現在のバージョンを引き続き使用します。|업데이트를 설치하지 못했습니다. 현재 버전을 유지합니다.
Updates are ready. Quit and reopen MyStatus to load them.|Les mises à jour sont prêtes. Quittez et rouvrez MyStatus pour les charger.|Updates sind bereit. Beende und öffne MyStatus erneut, um sie zu laden.|アップデートの準備ができました。MyStatus を終了して開き直してください。|업데이트가 준비되었습니다. 적용하려면 MyStatus를 다시 실행하세요.
Upload/download rates, total traffic, and network interfaces.|Débits d’envoi et de réception, trafic total et interfaces réseau.|Upload- und Download-Raten, Gesamtverkehr und Netzwerkschnittstellen.|アップロードとダウンロードの速度、総通信量、ネットワークインターフェイス。|업로드 및 다운로드 속도, 총 트래픽 및 네트워크 인터페이스입니다.
Uses Caldis/Mos scroll interpolation inside MyStatus.|Utilise l’interpolation de défilement de Caldis/Mos dans MyStatus.|Verwendet die Scroll-Interpolation von Caldis/Mos in MyStatus.|Caldis/Mos のスクロール補間を MyStatus 内で使用します。|MyStatus 안에서 Caldis/Mos의 스크롤 보간을 사용합니다.
Using software dimming.|Atténuation logicielle active.|Software-Dimmung ist aktiv.|ソフトウェア減光を使用しています。|소프트웨어 디밍을 사용 중입니다.
Volume cannot be adjusted|Le volume ne peut pas être réglé|Die Lautstärke kann nicht geregelt werden|音量を調整できません|음량을 조절할 수 없습니다
Volume control requires macOS 14.2 or later.|Le réglage du volume nécessite macOS 14.2 ou une version ultérieure.|Die Lautstärkeregelung erfordert macOS 14.2 oder neuer.|音量調整には macOS 14.2 以降が必要です。|음량 제어에는 macOS 14.2 이상이 필요합니다.
Waiting for the display…|En attente de l’écran…|Warten auf das Display …|ディスプレイからの応答を待っています…|디스플레이 응답 대기 중…
%ldd %ldh|%ld j %ld h|%ld T %ld Std.|%ld 日 %ld 時間|%ld일 %ld시간
%ldh %ldmin|%ld h %ld min|%ld Std. %ld Min.|%ld 時間 %ld 分|%ld시간 %ld분
%ld min|%ld min|%ld Min.|%ld 分|%ld분
%ld min ago|il y a %ld min|vor %ld Min.|%ld 分前|%ld분 전
%ldh ago|il y a %ld h|vor %ld Std.|%ld 時間前|%ld시간 전
%ldd ago|il y a %ld j|vor %ld T.|%ld 日前|%ld일 전
Brightness|Luminosité|Helligkeit|輝度|밝기
Contrast|Contraste|Kontrast|コントラスト|대비
Full history %@|Tout l’historique %@|Vollständiger Verlauf %@|すべての履歴 %@|전체 기록 %@
Pinned items are exempt. %1$@ items, about %2$@.|Les éléments épinglés sont exclus de ces limites. %1$@ éléments, environ %2$@.|Angeheftete Einträge sind ausgenommen. %1$@ Einträge, etwa %2$@.|固定した項目は制限の対象外です。%1$@ 件、約 %2$@。|고정한 항목은 제한에서 제외됩니다. %1$@개, 약 %2$@.
Excluded apps (%@)|Apps exclues (%@)|Ausgeschlossene Apps (%@)|除外するアプリ（%@）|제외할 앱(%@)
Virtual devices (%@)|Périphériques virtuels (%@)|Virtuelle Geräte (%@)|仮想デバイス（%@）|가상 기기(%@)
All sensors (%@)|Tous les capteurs (%@)|Alle Sensoren (%@)|すべてのセンサー（%@）|모든 센서(%@)
%@ available|%@ disponibles|%@ verfügbar|空き %@|%@ 사용 가능
Time until full|Temps avant la charge complète|Zeit bis voll geladen|充電完了まで|완전히 충전되기까지
Time remaining|Temps restant|Verbleibende Zeit|残り時間|남은 시간
Software volume did not start: %@|Le volume logiciel n’a pas démarré : %@|Software-Lautstärke konnte nicht gestartet werden: %@|ソフトウェア音量を開始できませんでした：%@|소프트웨어 음량을 시작하지 못했습니다: %@
Could not load: %@|Impossible de charger : %@|Konnte nicht geladen werden: %@|読み込めませんでした：%@|불러오지 못했습니다: %@
Built for plug-in API %1$@. MyStatus requires %2$@.|Conçu pour l’API de module %1$@. MyStatus requiert la version %2$@.|Für Plug-in-API %1$@ erstellt. MyStatus benötigt Version %2$@.|プラグイン API %1$@ 向けです。MyStatus には %2$@ が必要です。|플러그인 API %1$@용으로 빌드되었습니다. MyStatus에는 %2$@ 버전이 필요합니다.
The library does not export %@|La bibliothèque n’exporte pas %@|Die Bibliothek exportiert %@ nicht|ライブラリに %@ が公開されていません|라이브러리가 %@을(를) 내보내지 않습니다
The declared ID (%@) does not match plugin.json.|L’identifiant déclaré (%@) ne correspond pas à plugin.json.|Die angegebene ID (%@) stimmt nicht mit plugin.json überein.|宣言された ID（%@）が plugin.json と一致しません。|선언된 ID(%@)가 plugin.json과 일치하지 않습니다.
The plug-in “%@” was disabled after it caused the app to quit at launch.|Le module « %@ » a été désactivé après avoir provoqué la fermeture de l’app au démarrage.|Das Plug-in „%@“ wurde deaktiviert, nachdem die App beim Start beendet wurde.|起動時にアプリが終了したため、プラグイン「%@」を無効にしました。|‘%@’ 플러그인이 시작 시 앱을 종료시켜 비활성화했습니다.
Finder|Finder|Finder|Finder|Finder
GPU|GPU|GPU|GPU|GPU
SSD|SSD|SSD|SSD|SSD
%ld displays|%ld écrans|%ld Displays|%ld 台|%ld대
%ld connected|%ld appareils connectés|%ld Geräte verbunden|%ld 台接続済み|%ld대 연결됨
1 connected|1 appareil connecté|1 Gerät verbunden|1 台接続済み|1대 연결됨
%ld items|%ld éléments|%ld Einträge|%ld 件|%ld개
1 item|1 élément|1 Eintrag|1 件|1개
Paused|En pause|Pausiert|一時停止中|일시 정지됨
Shortcut %@ is already in use|Le raccourci %@ est déjà utilisé|Kurzbefehl %@ wird bereits verwendet|ショートカット %@ は使用中です|단축키 %@을(를) 이미 사용 중입니다
Image %@|Image %@|Bild %@|画像 %@|이미지 %@
Image|Image|Bild|画像|이미지
%1$@ and %2$@ other files|%1$@ et %2$@ autres fichiers|%1$@ und %2$@ weitere Dateien|%1$@ ほか %2$@ 件|%1$@ 외 %2$@개 파일
%@ and one other file|%@ et un autre fichier|%@ und eine weitere Datei|%@ ほか 1 件|%@ 외 파일 1개
Drag to reorder|Glisser pour réorganiser|Zum Sortieren ziehen|ドラッグして並べ替え|드래그하여 순서 변경
Move up|Déplacer vers le haut|Nach oben bewegen|上に移動|위로 이동
Move down|Déplacer vers le bas|Nach unten bewegen|下に移動|아래로 이동
Preview menu bar panel|Prévisualiser le panneau de la barre des menus|Menüleistenpanel anzeigen|メニューバーパネルをプレビュー|메뉴 막대 패널 미리보기
Open Input Monitoring|Ouvrir Surveillance de l’entrée|Eingabeüberwachung öffnen|入力監視を開く|입력 모니터링 열기
Hardware brightness key listener is active.|La détection matérielle des touches de luminosité est active.|Hardware-Erkennung für Helligkeitstasten aktiv.|ハードウェア輝度キーの監視が有効です。|하드웨어 밝기 키 수신이 활성화되었습니다.
Could not start the hardware brightness key listener.|Impossible d’activer la détection matérielle des touches de luminosité.|Hardware-Erkennung für Helligkeitstasten konnte nicht gestartet werden.|ハードウェア輝度キーの監視を開始できませんでした。|하드웨어 밝기 키 수신을 시작하지 못했습니다.
Hardware brightness keys need Input Monitoring when only external displays are active.|La surveillance de l’entrée est requise pour les touches de luminosité lorsque seuls des écrans externes sont actifs.|Wenn nur externe Monitore aktiv sind, benötigen die Hardware-Helligkeitstasten die Eingabeüberwachung.|外部ディスプレイのみが有効な場合、ハードウェア輝度キーには入力監視が必要です。|외장 디스플레이만 활성화된 경우 하드웨어 밝기 키에 입력 모니터링 권한이 필요합니다.
"""#
}
