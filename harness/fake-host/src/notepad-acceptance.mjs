import { validateNotepadAcceptance } from "@veil/protocol";

export function summarizeNotepadLaunch({ launch, window }) {
  return {
    accepted: true,
    ...validateNotepadAcceptance(launch, window)
  };
}
