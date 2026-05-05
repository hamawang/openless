import {
  getCapsuleHostMetrics,
  getCapsuleMessageLayout,
  getCapsulePillMetrics,
} from './capsuleLayout.ts';

function assertEqual<T>(actual: T, expected: T, name: string) {
  if (actual !== expected) {
    throw new Error(`${name}: expected ${expected}, got ${actual}`);
  }
}

const winMetrics = getCapsulePillMetrics('win');
assertEqual(winMetrics.width, 196, 'windows capsule widens pill');
assertEqual(winMetrics.height, 52, 'windows capsule increases pill height');
assertEqual(winMetrics.textWidth, 118, 'windows capsule widens text slot');

const winHost = getCapsuleHostMetrics('win', false);
assertEqual(winHost.width, 220, 'windows capsule host keeps the current outer hitbox width');
assertEqual(winHost.height, 84, 'windows capsule host keeps regular height');
assertEqual(winHost.horizontalInset, 12, 'windows capsule host keeps symmetric shadow insets');
assertEqual(
  winHost.width,
  winMetrics.width + winHost.horizontalInset * 2,
  'windows capsule host width derives from pill width plus symmetric side insets',
);

const winHostWithTranslation = getCapsuleHostMetrics('win', true);
assertEqual(winHostWithTranslation.width, 220, 'windows translation capsule keeps the same outer width');
assertEqual(winHostWithTranslation.height, 118, 'windows translation capsule grows vertically only');
assertEqual(winHostWithTranslation.horizontalInset, 12, 'windows translation capsule keeps symmetric side insets');

const macMetrics = getCapsulePillMetrics('mac');
assertEqual(macMetrics.width, 176, 'mac capsule keeps existing pill width');
assertEqual(macMetrics.height, 42, 'mac capsule keeps existing pill height');
assertEqual(macMetrics.textWidth, 84, 'mac capsule keeps existing text slot');

const winErrorLayout = getCapsuleMessageLayout('win', 'error');
assertEqual(winErrorLayout.lineClamp, 2, 'windows error message allows two lines');
assertEqual(winErrorLayout.allowWrap, true, 'windows error message wraps');

const winProcessingLayout = getCapsuleMessageLayout('win', 'processing');
assertEqual(winProcessingLayout.lineClamp, 2, 'windows processing label allows two lines');
assertEqual(winProcessingLayout.allowWrap, true, 'windows processing label wraps');

const macErrorLayout = getCapsuleMessageLayout('mac', 'error');
assertEqual(macErrorLayout.lineClamp, 1, 'mac error message stays single-line');
assertEqual(macErrorLayout.allowWrap, false, 'mac error message stays nowrap');
