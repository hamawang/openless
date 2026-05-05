import type { zhCN } from './zh-CN';
import { en } from './en';

// Japanese locale scaffold (incremental translation over English baseline).
export const ja: typeof zhCN = {
  ...en,
  app: {
    ...en.app,
    tagline: '自然に話し、きれいに書く',
  },
  settings: {
    ...en.settings,
    language: {
      ...en.settings.language,
      title: '表示言語',
      desc: 'UI の表示言語を切り替えます。現在のセッションに即時反映され、次回起動時も維持されます。',
      label: '言語',
      labelDesc: '「システムに従う」を選ぶと OS の言語に合わせます。',
      followSystem: 'システムに従う',
      zh: '简体中文',
      zhTW: '繁體中文',
      en: 'English',
      ja: '日本語',
      ko: '한국어',
      restartHint: '一部のネイティブメニュー（トレイ等）は再起動後に反映されます。',
    },
  },
  modal: {
    ...en.modal,
    personalize: {
      ...en.modal.personalize,
      language: '表示言語',
    },
  },
};
