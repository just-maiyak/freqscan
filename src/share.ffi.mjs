import { Ok, Error } from "./gleam.mjs";

export function can_share() {
    return navigator.canShare
}

export function share_image(image_data) {
  const image_u8_array = Uint8Array.from(
      window.atob(image_data),
      v => v.charCodeAt(0)
  )
  const image_file = new File(
    [image_u8_array], "ma_frequence.png", {
        type: "image/png",
        lastModified: new Date().getTime(),
      }
  );
  const share_data = {
    title: "Ma fréquence stationR",
    files: [image_file]
  };

  if (navigator.canShare && navigator.canShare(share_data)) {
    try {
        Promise.resolve(navigator.share(share_data));
    } catch (error) {
        return new Error(`Erreur: ${error.message}`)
    }
    return new Ok(undefined);
  } else {
    return new Error("Le navigateur ne supporte pas le partage de fichiers.");
  }
}
