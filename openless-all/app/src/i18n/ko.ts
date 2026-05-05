import type { zhCN } from './zh-CN';
import { en } from './en';

// Korean locale scaffold (incremental translation over English baseline).
export const ko: typeof zhCN = {
  ...en,
  app: {
    ...en.app,
    tagline: '자연스럽게 말하고, 정확하게 작성하세요',
  },
  settings: {
    ...en.settings,
    language: {
      ...en.settings.language,
      title: '인터페이스 언어',
      desc: 'UI 표시 언어를 전환합니다. 현재 세션에 즉시 반영되며 다음 실행에도 유지됩니다.',
      label: '언어',
      labelDesc: '"시스템 따라가기"를 선택하면 OS 언어를 따릅니다.',
      followSystem: '시스템 따라가기',
      zh: '简体中文',
      zhTW: '繁體中文',
      en: 'English',
      ja: '日本語',
      ko: '한국어',
      restartHint: '일부 네이티브 메뉴(트레이 등)는 앱 재시작 후 반영될 수 있습니다.',
    },
  },
  modal: {
    ...en.modal,
    personalize: {
      ...en.modal.personalize,
      language: '인터페이스 언어',
    },
  },
};
