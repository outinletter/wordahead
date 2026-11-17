#!/usr/bin/env python3
import json
import os
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
i18n_path = root / 'i18n.js'
content = i18n_path.read_text('utf-8')

langs = ['de', 'ja', 'zh-Hans', 'es-MX', 'fr-FR', 'it', 'pt-BR', 'ru', 'nl', 'th']

new_translations = {
    '화면': [
        'Bildschirm', '画面', '屏幕', 'Pantalla', 'Affichage',
        'Schermo', 'Tela', 'Экран', 'Scherm', 'หน้าจอ'
    ],
    '화면 모드': [
        'Erscheinungsbild', '外観モード', '外观模式', 'Aspecto', 'Apparence',
        'Aspetto', 'Aparência', 'Оформление', 'Weergave', 'โหมดลักษณะ'
    ],
    '시스템 설정': [
        'System', 'システム設定', '跟随系统', 'Del sistema', 'Réglages système',
        'Di sistema', 'Do sistema', 'Системные', 'Systeem', 'ตามระบบ'
    ],
    '밝게': [
        'Hell', 'ライト', '浅色', 'Claro', 'Clair',
        'Chiaro', 'Claro', 'Светлая', 'Licht', 'สว่าง'
    ],
    '어둡게': [
        'Dunkel', 'ダーク', '深色', 'Oscuro', 'Sombre',
        'Scuro', 'Escuro', 'Тёмная', 'Donker', 'มืด'
    ],
    '자막과 먼저 살펴볼 단어의 글자 크기는 해당 화면에서 조절할 수 있습니다.': [
        'Die Schriftgröße für Untertitel und Vokabeln kann auf dem jeweiligen Bildschirm angepasst werden.',
        '字幕と予習単語の文字サイズは各画面で調整できます。',
        '字幕和预习单词的字体大小可在相应界面中调整。',
        'El tamaño de letra de los subtítulos y palabras previas se puede ajustar en cada pantalla.',
        'La taille de police des sous-titres et des mots clés peut être ajustée sur chaque écran.',
        'La dimensione del testo per sottotitoli e vocaboli può essere modificata nella relativa schermata.',
        'O tamanho da fonte das legendas e das palavras prévias pode ser ajustado em cada tela.',
        'Размер шрифта субтитров и слов для изучения настраивается на соответствующем экране.',
        'De tekstgrootte voor ondertitels en woordenschat kan op het betreffende scherm worden aangepast.',
        'สามารถปรับขนาดตัวอักษรของคำบรรยายและคำศัพท์ได้ในแต่ละหน้าจอ'
    ],
    '오프라인 학습': [
        'Offline-Lernen', 'オフライン学習', '离线学习', 'Aprendizaje sin conexión', 'Apprentissage hors ligne',
        'Apprendimento offline', 'Aprendizado offline', 'Офлайн-обучение', 'Offline leren', 'การเรียนรู้ออฟไลน์'
    ],
    '내장 영한 사전 49,527개': [
        'Integriertes Wörterbuch (49.527 Einträge)', '内蔵英韓辞書 49,527語', '内置英韩词典 49,527词',
        'Diccionario integrado (49.527 entradas)', 'Dictionnaire intégré (49 527 entrées)',
        'Dizionario integrato (49.527 voci)', 'Dicionário integrado (49.527 entradas)',
        'Встроенный словарь (49 527 слов)', 'Ingebouwd woordenboek (49.527 woorden)',
        'พจนานุกรมในตัว 49,527 คำ'
    ],
    '저장한 자막, 단어와 한글 뜻은 인터넷 없이 열 수 있습니다. 영상 재생과 최초 자막 수집은 인터넷이 필요합니다.': [
        'Gespeicherte Untertitel, Wörter und Bedeutungen sind offline verfügbar. Videowiedergabe und erster Abruf erfordern Internet.',
        '保存した字幕、単語、意味はオフラインで確認できます。動画再生と最初の字幕取得にはインターネットが必要です。',
        '已保存的字幕、单词与释义无需网络即可查看。视频播放与首次字幕获取需要网络。',
        'Los subtítulos, palabras y significados guardados se abren sin conexión. Reproducción y descarga inicial requieren internet.',
        'Les sous-titres, mots et définitions enregistrés sont accessibles hors ligne. La lecture et le premier import nécessitent internet.',
        'Sottotitoli, parole e significati salvati sono disponibili offline. Riproduzione e primo download richiedono internet.',
        'Legendas, palavras e significados salvos podem ser acessados sem internet. Reprodução e download inicial exigem internet.',
        'Сохранённые субтитры, слова и значения доступны офлайн. Воспроизведение и первая загрузка требуют интернета.',
        'Opgeslagen ondertitels, woorden en betekenissen zijn offline beschikbaar. Videoweergave en eerste import vereisen internet.',
        'คำบรรยาย คำศัพท์ และความหมายที่บันทึกไว้เปิดได้โดยไม่ต้องใช้อินเทอร์เน็ต การเล่นและการดึงครั้งแรกต้องใช้อินเทอร์เน็ต'
    ],
    'Plus 이용 중': [
        'Plus aktiv', 'Plus利用中', 'Plus使用中', 'Plus activo', 'Plus actif',
        'Plus attivo', 'Plus ativo', 'Plus активен', 'Plus actief', 'กำลังใช้งาน Plus'
    ],
    '구독 상품을 불러올 수 없습니다. 무료 학습은 계속 이용할 수 있습니다.': [
        'Abonnements konnten nicht geladen werden. Kostenloses Lernen ist weiterhin verfügbar.',
        '定期購入商品を読み込めませんでした。無料学習は引き続き利用できます。',
        '无法加载订阅商品。免费学习功能仍可继续使用。',
        'No se pudieron cargar las suscripciones. El aprendizaje gratuito sigue disponible.',
        'Impossible de charger les abonnements. L’apprentissage gratuit reste accessible.',
        'Impossibile caricare gli abbonamenti. L’apprendimento gratuito resta disponibile.',
        'Não foi possível carregar as assinaturas. O aprendizado gratuito continua disponível.',
        'Не удалось загрузить подписки. Бесплатное обучение по-прежнему доступно.',
        'Abonnementen konden niet worden geladen. Gratis leren blijft beschikbaar.',
        'ไม่สามารถโหลดรายการสมาชิกได้ แต่ยังเรียนรู้ฟรีได้ตามปกติ'
    ],
    '상품 다시 확인': [
        'Erneut prüfen', '再確認', '重新检查', 'Comprobar de nuevo', 'Vérifier à nouveau',
        'Ricontrolla', 'Verificar novamente', 'Проверить снова', 'Opnieuw controleren', 'ตรวจสอบอีกครั้ง'
    ],
    '무료로 하루 새 영상 2개를 분석할 수 있습니다. 기존 자막·단어장 복습과 영상 재생은 계속 이용할 수 있습니다.': [
        'Zwei neue Videoanalysen pro Tag sind kostenlos. Vorhandene Untertitel, Wortlisten und Videowiedergabe bleiben verfügbar.',
        '新しい動画は1日2本まで無料で分析できます。既存の字幕・単語帳の復習と動画再生は引き続き利用できます。',
        '每天可免费分析2个新视频。现有字幕、单词本复习和视频播放仍可使用。',
        'Puedes analizar gratis 2 videos nuevos al día. Subtítulos, listas existentes y reproducción de video siguen disponibles.',
        'Vous pouvez analyser gratuitement 2 nouvelles vidéos par jour. Les sous-titres, listes et la lecture vidéo restent disponibles.',
        'Puoi analizzare gratis 2 nuovi video al giorno. Sottotitoli, liste esistenti e riproduzione video restano disponibili.',
        'Você pode analisar 2 vídeos novos por dia gratuitamente. Legendas, listas e reprodução de vídeo continuam disponíveis.',
        'Бесплатно доступны 2 анализа новых видео в день. Субтитры, списки слов и воспроизведение видео остаются доступны.',
        'Je kunt dagelijks 2 nieuwe video’s gratis analyseren. Bestaande ondertitels, woordenlijsten en videoweergave blijven beschikbaar.',
        'วิเคราะห์วิดีโอใหม่ได้ฟรีวันละ 2 รายการ และยังทบทวนคำบรรยาย รายการคำศัพท์เดิม รวมถึงเล่นวิดีโอได้'
    ],
    '자동 갱신 구독이며 취소 전까지 매년 갱신됩니다. 결제 금액은 Apple 결제 화면에서 확인하세요.': [
        'Automatisch verlängerbares Jahresabo. Preis und Bedingungen werden vor dem Kauf von Apple angezeigt.',
        '毎年自動更新される定期購入です。料金と期間はAppleの購入画面でご確認ください。',
        '按年自动续订。价格和详细信息请在Apple支付页面确认。',
        'Suscripción anual con renovación automática. Consulta el precio en la pantalla de Apple.',
        'Abonnement annuel avec renouvellement automatique. Vérifiez le montant sur l’écran Apple.',
        'Abbonamento con rinnovo annuale automatico. Verifica l’importo nella schermata Apple.',
        'Assinatura com renovação anual automática. Verifique o valor na tela da Apple.',
        'Ежегодная подписка с автопродлением. Стоимость указана на экране оплаты Apple.',
        'Abonnement met jaarlijkse automatische verlenging. Bekijk de prijs in het Apple-betaalscherm.',
        'สมัครสมาชิกแบบต่ออายุรายปีอัตโนมัติ ตรวจสอบยอดชำระได้ที่หน้าต่าง Apple'
    ],
    '학습 데이터': [
        'Lerndaten', '学習データ', '学习数据', 'Datos de aprendizaje', 'Données d’apprentissage',
        'Dati di apprendimento', 'Dados de aprendizado', 'Данные обучения', 'Leergegevens', 'ข้อมูลการเรียน'
    ],
    '알고 있는 단어 내보내기': [
        'Bekannte Wörter exportieren', '知っている単語を書き出す', '导出已掌握单词',
        'Exportar palabras conocidas', 'Exporter les mots connus', 'Esporta parole conosciute',
        'Exportar palavras conhecidas', 'Экспортировать известные слова', 'Bekende woorden exporteren',
        'ส่งออกคำที่รู้แล้ว'
    ],
    '알고 있는 단어 가져오기': [
        'Bekannte Wörter importieren', '知っている単語を読み込む', '导入已掌握单词',
        'Importar palabras conocidas', 'Importer les mots connus', 'Importa parole conosciute',
        'Importar palavras conhecidas', 'Импортировать известные слова', 'Bekende woorden importeren',
        'นำเข้าคำที่รู้แล้ว'
    ],
    '정보': [
        'Info', '情報', '关于', 'Información', 'Informations',
        'Informazioni', 'Informações', 'Информация', 'Informatie', 'ข้อมูล'
    ],
    '도움말 및 문의': [
        'Hilfe & Support', 'ヘルプ・お問い合わせ', '帮助与支持', 'Ayuda y soporte', 'Aide et assistance',
        'Guida e supporto', 'Ajuda e suporte', 'Справка и поддержка', 'Help en contact', 'ช่วยเหลือและติดต่อ'
    ],
    '오픈소스 사전 출처·라이선스': [
        'Open-Source-Quellen & Lizenzen', 'オープンソース辞書の出典・ライセンス', '开源词典来源与许可',
        'Fuentes y licencias del diccionario', 'Sources et licences du dictionnaire',
        'Fonti e licenze del dizionario open source', 'Fontes e licenças do dicionário de código aberto',
        'Источники и лицензии словаря', 'Open-source bronnen en licenties',
        'แหล่งที่มาและสัญญาอนุญาตพจนานุกรมโอเพนซอร์ส'
    ],
    '버전': [
        'Version', 'バージョン', '版本', 'Versión', 'Version',
        'Versione', 'Versão', 'Версия', 'Versie', 'เวอร์ชัน'
    ],
    '저장한 자막과 단어장, 학습 기록을 모두 삭제할까요?': [
        'Alle gespeicherten Untertitel, Wortlisten und Lerndaten löschen?',
        '保存した字幕、単語帳、学習履歴をすべて削除しますか？',
        '确定要删除所有已保存的字幕、单词本与学习记录吗？',
        '¿Eliminar todos los subtítulos, listas y registros de aprendizaje guardados?',
        'Supprimer tous les sous-titres, listes de mots et historiques enregistrés ?',
        'Eliminare tutti i sottotitoli, le liste di parole e i progressi salvati?',
        'Excluir todas as legendas, listas de palavras e registros de aprendizado salvos?',
        'Удалить все сохранённые субтитры, словари и историю обучения?',
        'Alle opgeslagen ondertitels, woordenlijsten en leergeschiedenis wissen?',
        'ต้องการลบคำบรรยาย รายการคำศัพท์ และบันทึกการเรียนทั้งหมดที่บันทึกไว้หรือไม่'
    ],
    '모두 삭제': [
        'Alles löschen', 'すべて削除', '全部删除', 'Eliminar todo', 'Tout supprimer',
        'Elimina tutto', 'Excluir tudo', 'Удалить всё', 'Alles wissen', 'ลบทั้งหมด'
    ],
    '오픈소스 라이선스': [
        'Open-Source-Lizenzen', 'オープンソースライセンス', '开源许可', 'Licencias de código abierto',
        'Licences open source', 'Licenze open source', 'Licenças de código aberto',
        'Лицензии с открытым исходным кодом', 'Open-sourcelicenties', 'สัญญาอนุญาตโอเพนซอร์ส'
    ],
    '안내': [
        'Hinweis', 'お知らせ', '提示', 'Aviso', 'Information',
        'Avviso', 'Aviso', 'Уведомление', 'Melding', 'แจ้งเตือน'
    ],
    '확인': [
        'OK', 'OK', '确定', 'Aceptar', 'OK',
        'OK', 'OK', 'ОК', 'OK', 'ตกลง'
    ],
    '영상이나 자막을 추가해 첫 학습을 시작하세요.': [
        'Füge ein Video oder Untertitel hinzu, um mit dem Lernen zu beginnen.',
        '動画や字幕を追加して、最初の学習を始めましょう。',
        '添加视频或字幕，开启你的第一次学习。',
        'Agrega un video o subtítulos para empezar tu primer estudio.',
        'Ajoutez une vidéo ou des sous-titres pour commencer.',
        'Aggiungi un video o dei sottotitoli per iniziare a studiare.',
        'Adicione um vídeo ou legendas para começar seu primeiro estudo.',
        'Добавьте видео или субтитры, чтобы начать первое занятие.',
        'Voeg een video of ondertitels toe om te beginnen met leren.',
        'เพิ่มวิดีโอหรือคำบรรยายเพื่อเริ่มการเรียนรู้ครั้งแรก'
    ],
    '자막 수집 중…': [
        'Untertitel werden geladen…', '字幕を取得中…', '正在获取字幕…', 'Obteniendo subtítulos…',
        'Récupération des sous-titres…', 'Recupero sottotitoli in corso…', 'Coletando legendas…',
        'Сбор субтитров…', 'Ondertitels ophalen…', 'กำลังดึงคำบรรยาย…'
    ],
    '자막 수집 필요': [
        'Untertitel erforderlich', '字幕の取得が必要', '需要获取字幕', 'Se requieren subtítulos',
        'Sous-titres requis', 'Sottotitoli necessari', 'Legendas necessárias', 'Требуются субтитры',
        'Ondertitels vereist', 'ต้องดึงคำบรรยาย'
    ],
    '자막 저장됨 · 오프라인 복습': [
        'Untertitel gespeichert · Offline-Wiederholung', '字幕保存済み · オフライン復習',
        '字幕已保存 · 离线复习', 'Subtítulos guardados · Repaso sin conexión',
        'Sous-titres enregistrés · Révision hors ligne', 'Sottotitoli salvati · Ripasso offline',
        'Legendas salvas · Revisão offline', 'Субтитры сохранены · Офлайн-повторение',
        'Ondertitels opgeslagen · Offline herhalen', 'บันทึกคำบรรยายแล้ว · ทบทวนแบบออฟไลน์'
    ],
    '영상 삭제': [
        'Video löschen', '動画を削除', '删除视频', 'Eliminar video', 'Supprimer la vidéo',
        'Elimina video', 'Excluir vídeo', 'Удалить видео', 'Video verwijderen', 'ลบวิดีโอ'
    ],
    '추가 방법': [
        'Methode auswählen', '追加方法', '添加方式', 'Método de adición', 'Mode d’ajout',
        'Metodo di aggiunta', 'Método de adição', 'Способ добавления', 'Methode kiezen', 'วิธีเพิ่ม'
    ],
    'YouTube 링크': [
        'YouTube-Link', 'YouTubeリンク', 'YouTube链接', 'Enlace de YouTube', 'Lien YouTube',
        'Link YouTube', 'Link do YouTube', 'Ссылка YouTube', 'YouTube-link', 'ลิงก์ YouTube'
    ],
    '자막 직접 입력': [
        'Untertitel manuell eingeben', '字幕を直接入力', '手动输入字幕',
        'Ingresar subtítulos directamente', 'Saisir les sous-titres manuellement',
        'Inserisci sottotitoli manualmente', 'Inserir legendas diretamente',
        'Ввести субтитры вручную', 'Ondertitels handmatig invoeren', 'ป้อนคำบรรยายเอง'
    ],
    '영상 주소': [
        'Video-URL', '動画URL', '视频网址', 'URL del video', 'URL de la vidéo',
        'URL del video', 'URL do vídeo', 'Адрес видео', 'Video-URL', 'ที่อยู่วิดีโอ'
    ],
    '수집 가능한 영어 자막을 저장합니다. 제한된 영상은 자막을 직접 입력할 수 있습니다.': [
        'Verfügbare englische Untertitel werden gespeichert. Bei Einschränkungen können Texte manuell eingegeben werden.',
        '取得可能な英語字幕を保存します。制限のある動画は字幕を直接入力できます。',
        '将保存可获取的英语字幕。受限视频可手动输入字幕。',
        'Se guardarán los subtítulos en inglés disponibles. Para videos restringidos, puedes ingresarlos manualmente.',
        'Enregistre les sous-titres anglais disponibles. Pour les vidéos restreintes, saisissez-les manuellement.',
        'Salva i sottotitoli in inglese disponibili. Per i video limitati, puoi inserirli manualmente.',
        'Salva as legendas em inglês disponíveis. Para vídeos restritos, você pode inseri-las diretamente.',
        'Будут сохранены доступные английские субтитры. Для ограниченных видео можно ввести субтитры вручную.',
        'Beschikbare Engelse ondertitels worden opgeslagen. Bij beperkte video’s kun je ze handmatig invoeren.',
        'บันทึกคำบรรยายภาษาอังกฤษที่ดึงได้ สำหรับวิดีโอที่จำกัดสามารถป้อนคำบรรยายเองได้'
    ],
    '내 자막': [
        'Eigene Untertitel', 'マイ字幕', '我的字幕', 'Mis subtítulos', 'Mes sous-titres',
        'I miei sottotitoli', 'Minhas legendas', 'Мои субтитры', 'Mijn ondertitels', 'คำบรรยายของฉัน'
    ],
    '제목': [
        'Titel', 'タイトル', '标题', 'Título', 'Titre',
        'Titolo', 'Título', 'Название', 'Titel', 'ชื่อเรื่อง'
    ],
    '영어 자막 본문': [
        'Englischer Untertiteltext', '英語字幕本文', '英语字幕正文', 'Texto de subtítulos en inglés',
        'Texte des sous-titres anglais', 'Testo dei sottotitoli in inglese', 'Texto das legendas em inglês',
        'Текст английских субтитров', 'Tekst van Engelse ondertitels', 'เนื้อหาคำบรรยายภาษาอังกฤษ'
    ],
    '직접 작성했거나 사용 권한이 있는 자막을 입력하세요.': [
        'Gib selbst verfasste oder autorisierte Untertitel ein.',
        '自作または使用権限のある字幕を入力してください。',
        '请输入自己编写或拥有使用权限的字幕。',
        'Ingresa subtítulos creados por ti o con permiso de uso.',
        'Saisissez des sous-titres créés par vous-même ou autorisés.',
        'Inserisci sottotitoli creati da te o autorizzati.',
        'Insira legendas criadas por você ou com permissão de uso.',
        'Введите субтитры, созданные вами или разрешённые к использованию.',
        'Voer zelfgeschreven of geautoriseerde ondertitels in.',
        'โปรดป้อนคำบรรยายที่คุณเขียนขึ้นเองหรือได้รับสิทธิ์ใช้งาน'
    ],
    '자막 직접 입력하기': [
        'Untertitel manuell eingeben', '字幕を直接入力する', '手动输入字幕',
        'Ingresar subtítulos directamente', 'Saisir les sous-titres',
        'Inserisci sottotitoli', 'Inserir legendas', 'Ввести субтитры вручную',
        'Ondertitels invoeren', 'ป้อนคำบรรยายเอง'
    ],
    '자막 가져오기': [
        'Untertitel abrufen', '字幕を取得', '获取字幕', 'Obtener subtítulos',
        'Récupérer les sous-titres', 'Scarica sottotitoli', 'Obter legendas',
        'Получить субтитры', 'Ondertitels ophalen', 'ดึงคำบรรยาย'
    ],
    '자막을 가져오는 중…': [
        'Untertitel werden geladen…', '字幕を読み込み中…', '正在加载字幕…', 'Cargando subtítulos…',
        'Chargement des sous-titres…', 'Caricamento sottotitoli…', 'Carregando legendas…',
        'Загрузка субтитров…', 'Ondertitels laden…', 'กำลังโหลดคำบรรยาย…'
    ],
    '자막을 찾을 수 없습니다.': [
        'Keine Untertitel gefunden.', '字幕が見つかりません。', '未找到字幕。',
        'No se encontraron subtítulos.', 'Sous-titres introuvables.', 'Sottotitoli non trovati.',
        'Legendas não encontradas.', 'Субтитры не найдены.', 'Geen ondertitels gevonden.',
        'ไม่พบคำบรรยาย'
    ],
    '이전 화면으로 돌아가기': [
        'Zurück', '前の画面へ戻る', '返回上一页', 'Volver', 'Retour',
        'Indietro', 'Voltar', 'Назад', 'Terug', 'กลับไปหน้าก่อน'
    ],
    '사전 닫기': [
        'Wörterbuch schließen', '辞書を閉じる', '关闭词典', 'Cerrar diccionario', 'Fermer le dictionnaire',
        'Chiudi dizionario', 'Fechar dicionário', 'Закрыть словарь', 'Woordenboek sluiten', 'ปิดพจนานุกรม'
    ],
    '단어 저장': [
        'Wort speichern', '単語を保存', '保存单词', 'Guardar palabra', 'Enregistrer le mot',
        'Salva parola', 'Salvar palavra', 'Сохранить слово', 'Woord opslaan', 'บันทึกคำศัพท์'
    ],
    '발음 듣기': [
        'Aussprache anhören', '発音を聞く', '收听发音', 'Escuchar pronunciación', 'Écouter la prononciation',
        'Ascolta pronuncia', 'Ouvir pronúncia', 'Прослушать произношение', 'Uitspraak beluisteren', 'ฟังการออกเสียง'
    ],
    '사전에서 뜻을 찾는 중…': [
        'Bedeutung wird im Wörterbuch gesucht…', '辞書で意味を検索中…', '正在词典中查询释义…',
        'Buscando significado en el diccionario…', 'Recherche de la définition dans le dictionnaire…',
        'Ricerca del significato nel dizionario…', 'Buscando significado no dicionário…',
        'Поиск значения в словаре…', 'Betekenis zoeken in het woordenboek…', 'กำลังค้นหาความหมายในพจนานุกรม…'
    ],
    '오프라인 사전 미수록 · 다시 조회': [
        'Nicht im Offline-Wörterbuch · Erneut suchen', 'オフライン辞書未収録 · 再検索',
        '离线词典未收录 · 重新查询', 'No disponible sin conexión · Buscar de nuevo',
        'Non inclus hors ligne · Rechercher à nouveau', 'Non nel dizionario offline · Cerca di nuovo',
        'Não incluído offline · Pesquisar novamente', 'Нет в офлайн-словаре · Повторить поиск',
        'Niet in offline woordenboek · Opnieuw zoeken', 'ไม่มีในพจนานุกรมออฟไลน์ · ค้นหาอีกครั้ง'
    ],
    '단어 상태': [
        'Wortstatus', '単語の状態', '单词状态', 'Estado de palabra', 'État du mot',
        'Stato della parola', 'Status da palavra', 'Статус слова', 'Woordstatus', 'สถานะคำศัพท์'
    ],
    '전체': [
        'Alle', 'すべて', '全部', 'Todo', 'Tout',
        'Tutto', 'Tudo', 'Все', 'Alles', 'ทั้งหมด'
    ],
    '저장한 단어가 없습니다.': [
        'Keine gespeicherten Wörter.', '保存した単語はありません。', '没有保存的单词。',
        'No hay palabras guardadas.', 'Aucun mot enregistré.', 'Nessuna parola salvata.',
        'Nenhuma palavra salva.', 'Нет сохранённых слов.', 'Geen opgeslagen woorden.', 'ไม่มีคำศัพท์ที่บันทึกไว้'
    ],
    '뜻 없음 · 눌러서 다시 조회': [
        'Keine Definition · Zum Suchen tippen', '意味なし · タップして再検索', '无释义 · 点击重新查询',
        'Sin significado · Toca para buscar', 'Aucune définition · Toucher pour rechercher',
        'Nessuna definizione · Tocca per cercare', 'Sem significado · Toque para buscar',
        'Нет значения · Нажмите для поиска', 'Geen definitie · Tik om te zoeken', 'ไม่มีความหมาย · แตะเพื่อค้นหาใหม่'
    ],
    '익히는 중으로 변경': [
        'Als "Beim Lernen" markieren', '学習中に変更', '标记为学习中', 'Cambiar a en aprendizaje',
        'Marquer comme à réviser', 'Segna come in apprendimento', 'Mudar para em aprendizado',
        'Отметить как изучаемое', 'Markeren als "Aan het leren"', 'เปลี่ยนเป็นกำลังเรียน'
    ],
    '알고 있는 단어로 변경': [
        'Als "Bekannt" markieren', '知っている単語に変更', '标记为已掌握', 'Cambiar a conocido',
        'Marquer comme connu', 'Segna come conosciuta', 'Mudar para conhecida',
        'Отметить как известное', 'Markeren als "Bekend"', 'เปลี่ยนเป็นคำที่รู้แล้ว'
    ],
    '단어 또는 한글 뜻 검색': [
        'Nach Wörtern oder Bedeutungen suchen', '単語または意味を検索', '搜索单词或释义',
        'Buscar palabra o significado', 'Rechercher un mot ou une définition', 'Cerca parola o significato',
        'Buscar palavra ou significado', 'Поиск по слову или значению', 'Zoeken op woord of betekenis',
        'ค้นหาคำศัพท์หรือความหมาย'
    ],
    '단어': [
        'Wort', '単語', '单词', 'Palabra', 'Mot',
        'Parola', 'Palavra', 'Слово', 'Woord', 'คำศัพท์'
    ],
    '뜻': [
        'Bedeutung', '意味', '释义', 'Significado', 'Définition',
        'Significato', 'Significado', 'Значение', 'Betekenis', 'ความหมาย'
    ],
    '알고 있는 단어로 표시': [
        'Als bekannt markieren', '知っている単語としてマーク', '标记为已知单词', 'Marcar como conocida',
        'Marquer comme connu', 'Segna come conosciuta', 'Marcar como conhecida',
        'Отметить как известное', 'Markeren als bekend', 'ทำเครื่องหมายว่ารู้แล้ว'
    ],
    '발음': [
        'Aussprache', '発音', '发音', 'Pronunciación', 'Prononciation',
        'Pronuncia', 'Pronúncia', 'Произношение', 'Uitspraak', 'การออกเสียง'
    ],
    '오프라인 사전 미수록 · 눌러서 조회': [
        'Nicht im Offline-Wörterbuch · Zum Suchen tippen', 'オフライン辞書未収録 · タップして検索',
        '离线词典未收录 · 点击查询', 'No disponible sin conexión · Toca para buscar',
        'Non inclus hors ligne · Toucher pour chercher', 'Non nel dizionario offline · Tocca per cercare',
        'Não incluído offline · Toque para buscar', 'Нет в офлайн-словаре · Нажмите для поиска',
        'Niet in offline woordenboek · Tik om te zoeken', 'ไม่มีในพจนานุกรมออฟไลน์ · แตะเพื่อค้นหา'
    ],
    '저장된 뜻 확인 중…': [
        'Gespeicherte Bedeutung wird geprüft…', '保存された意味を確認中…', '正在确认已保存释义…',
        'Comprobando significado guardado…', 'Vérification de la définition…', 'Controllo significato salvato…',
        'Verificando significado salvo…', 'Проверка сохранённого значения…',
        'Opgeslagen betekenis controleren…', 'กำลังตรวจสอบความหมายที่บันทึกไว้…'
    ],
    '닫기 ×': [
        'Schließen ×', '閉じる ×', '关闭 ×', 'Cerrar ×', 'Fermer ×',
        'Chiudi ×', 'Fechar ×', 'Закрыть ×', 'Sluiten ×', 'ปิด ×'
    ],
    'YouTube 자막 수집 중…': [
        'YouTube-Untertitel werden gesammelt…', 'YouTube字幕を取得中…', '正在收集YouTube字幕…',
        'Obteniendo subtítulos de YouTube…', 'Récupération des sous-titres YouTube…',
        'Raccolta sottotitoli YouTube in corso…', 'Coletando legendas do YouTube…',
        'Сбор субтитров YouTube…', 'YouTube-ondertitels ophalen…', 'กำลังรวบรวมคำบรรยาย YouTube…'
    ],
    'ENGLISH, ONE WORD AT A TIME': [
        'ENGLISCH, WORT FÜR WORT', '英語を、一歩ずつ確実に', '英语，循序渐进',
        'INGLÉS, PALABRA POR PALABRA', 'L’ANGLAIS, MOT APRÈS MOT',
        'INGLESE, UNA PAROLA ALLA VOLTA', 'INGLÊS, UMA PALAVRA POR VEZ',
        'АНГЛИЙСКИЙ, СЛОВО ЗА СЛОВОМ', 'ENGELS, WOORD VOOR WOORD',
        'ภาษาอังกฤษ ทีละคำอย่างมั่นใจ'
    ],
    'YOUR VOCABULARY': [
        'DEIN WORTSCHATZ', '単語帳', '我的生词本', 'TU VOCABULARIO',
        'VOTRE VOCABULAIRE', 'IL TUO VOCABOLARIO', 'SEU VOCABULÁRIO',
        'ВАШ СЛОВАРЬ', 'JOUW WOORDENSCHAT', 'คลังคำศัพท์ของคุณ'
    ],
    'YOUR LIBRARY': [
        'DEINE MEDIATHEK', 'ライブラリ', '我的视频库', 'TU BIBLIOTECA',
        'VOTRE BIBLIOTHÈQUE', 'LA TUA LIBRERIA', 'SUA BIBLIOTECA',
        'ВАША БИБЛИОТЕКА', 'JOUW BIBLIOTHEEK', 'คลังวิดีโอของคุณ'
    ]
}

# Parse existing rows from i18n.js
start_idx = content.find('  const rows={')
end_idx = content.find('  const reverse=')

# Extract keys and entries from rows={ ... };
# We'll build a python dictionary of all keys -> translations
existing_rows = {}

# Use regex to find all key-array mappings in i18n.js
pattern = re.compile(r'["\']([^"\']+)["\']\s*:\s*\[([\s\S]*?)\]', re.MULTILINE)
for match in pattern.finditer(content[start_idx:end_idx]):
    key = match.group(1)
    # Parse the array of string literals
    items_raw = match.group(2)
    items = re.findall(r'["\']((?:\\.|[^"\'])*)["\']', items_raw)
    items = [i.replace(r'\"', '"').replace(r"\'", "'").replace(r'\\', '\\') for i in items]
    if len(items) == 10:
        existing_rows[key] = items

print(f"Loaded {len(existing_rows)} existing translations from i18n.js")

# Merge new_translations into existing_rows
for k, v in new_translations.items():
    existing_rows[k] = v

aliases = {
    '설정': '환경설정',
    '학습': '학습할 영상',
    '단어장': '내 단어장',
    '자막 저장하기': '자막으로 시작하기',
    '영상·자막 추가': '영상 추가'
}
for alias_key, target_key in aliases.items():
    if target_key in existing_rows and alias_key not in existing_rows:
        existing_rows[alias_key] = existing_rows[target_key]

# Write out Localizable.strings for each language, plus ko.lproj
for index, lang in enumerate(langs):
    dir_path = root / 'ios' / 'Localizations' / f'{lang}.lproj'
    dir_path.mkdir(parents=True, exist_ok=True)
    strings_file = dir_path / 'Localizable.strings'
    lines = []
    for k, values in sorted(existing_rows.items()):
        val = values[index] if index < len(values) else k
        # Escape quotes and backslashes for .strings
        k_esc = json.dumps(k, ensure_ascii=False)
        v_esc = json.dumps(val, ensure_ascii=False)
        lines.append(f'{k_esc} = {v_esc};')
    strings_file.write_text('\n'.join(lines) + '\n', 'utf-8')
    print(f"Wrote {len(lines)} keys to {strings_file}")

# Write ko.lproj
ko_dir = root / 'ios' / 'Localizations' / 'ko.lproj'
ko_dir.mkdir(parents=True, exist_ok=True)
ko_strings_file = ko_dir / 'Localizable.strings'
ko_lines = []
for k in sorted(existing_rows.keys()):
    k_esc = json.dumps(k, ensure_ascii=False)
    ko_lines.append(f'{k_esc} = {k_esc};')
ko_strings_file.write_text('\n'.join(ko_lines) + '\n', 'utf-8')
print(f"Wrote {len(ko_lines)} keys to {ko_strings_file}")

print("Successfully updated all localizations!")
