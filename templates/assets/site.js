(() => {
  const calendar = document.querySelector("#year-calendar");
  const calendarToggle = document.querySelector(".calendar-toggle");

  if (calendar && calendarToggle) {
    calendarToggle.addEventListener("click", () => {
      const isOpen = calendar.dataset.open !== "true";
      calendar.dataset.open = isOpen.toString();
      calendarToggle.setAttribute("aria-expanded", isOpen.toString());
    });
  }

  const loadImage = (image) => {
    const picture = image.closest("picture");
    const source = picture?.querySelector("source[data-srcset]");

    if (source) {
      source.srcset = source.dataset.srcset;
      source.removeAttribute("data-srcset");
    }

    image.addEventListener("load", () => image.classList.add("loaded"), { once: true });
    image.src = image.dataset.src;
    image.removeAttribute("data-src");
    if (image.complete) image.classList.add("loaded");
  };

  const images = document.querySelectorAll("img[data-src]");

  if (!("IntersectionObserver" in window)) {
    images.forEach(loadImage);
  } else {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;

          loadImage(entry.target);
          observer.unobserve(entry.target);
        });
      },
      { rootMargin: "300px 0px" }
    );

    images.forEach((image) => observer.observe(image));
  }

  const lightbox = document.querySelector(".lightbox");
  const lightboxImage = lightbox?.querySelector(".lightbox-image");
  const closeButton = lightbox?.querySelector(".lightbox-close");

  if (!lightbox || !lightboxImage || !("showModal" in lightbox)) return;

  document.querySelectorAll(".lightbox-trigger").forEach((trigger) => {
    trigger.addEventListener("click", (event) => {
      event.preventDefault();
      lightboxImage.src = trigger.dataset.lightboxSrc;
      lightboxImage.alt = trigger.dataset.lightboxAlt;
      lightbox.showModal();
    });
  });

  closeButton.addEventListener("click", () => lightbox.close());
  lightbox.addEventListener("click", (event) => {
    if (event.target === lightbox) lightbox.close();
  });
})();
