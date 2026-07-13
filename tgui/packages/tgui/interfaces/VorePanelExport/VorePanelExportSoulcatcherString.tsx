import { SoulcatcherSettingsFlag } from './constants';
import { escapeHtml } from './functions';
import type { Soulcatcher } from './types';

// prettier-ignore
export const generateSoulcatcherString = (soulcatcher: Soulcatcher) => {
  const {
    name,
    inside_flavor,
    capture_message,
    transit_message,
    release_message,
    transfer_message,
    delete_message,
    linked_belly,
    setting_flags,
  } = soulcatcher;

  const index = 'sc_1';

  let result = '';
  result += `<div class="accordion-item"><h2 class="accordion-header" id="heading${index}">`;
  result += `<button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapse${index}" aria-expanded="false" aria-controls="collapse${index}">`;
  result += `${escapeHtml(name)} (Soulcatcher)`;
  result += '</button></h2>';

  result += `<div id="collapse${index}" class="accordion-collapse collapse" aria-labelledby="heading${index}" data-bs-parent="#accordionBellies">`;
  result += '<div class="accordion-body">';

  result += '<b>== Settings ==</b><br>';
  for (const flag in SoulcatcherSettingsFlag) {
    const isSet = (setting_flags & Number(flag)) !== 0;
    const badgeClass = isSet ? 'text-bg-success' : 'text-bg-danger';
    result += `<span class="badge ${badgeClass}">${SoulcatcherSettingsFlag[flag]}</span>`;
  }

  result += '<br><hr>';
  result += '<b>== Descriptions ==</b><br>';
  result += `Inside Flavor:<br>${escapeHtml(inside_flavor)}<br><br>`;
  result += `Capture Message:<br>${escapeHtml(capture_message)}<br><br>`;
  result += `Transit Message:<br>${escapeHtml(transit_message)}<br><br>`;
  result += `Release Message:<br>${escapeHtml(release_message)}<br><br>`;
  result += `Transfer Message:<br>${escapeHtml(transfer_message)}<br><br>`;
  result += `Delete Message:<br>${escapeHtml(delete_message)}<br><br>`;
  result += `Linked Belly:<br>${escapeHtml(linked_belly)}<br><br>`;

  result += '</div></div>';
  result += '</div>'; // End Div messagesTabpanel

  result += '</div></div></div>';

  return result;
};
