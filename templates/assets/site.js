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

  const subscribeMenu = document.querySelector(".subscribe-menu");
  const subscribeToggle = document.querySelector(".subscribe-toggle");

  if (subscribeMenu && subscribeToggle) {
    const setSubscribeOpen = (isOpen) => {
      subscribeMenu.dataset.open = isOpen.toString();
      subscribeToggle.setAttribute("aria-expanded", isOpen.toString());
    };

    subscribeToggle.addEventListener("click", () => {
      setSubscribeOpen(subscribeMenu.dataset.open !== "true");
    });

    document.addEventListener("click", (event) => {
      if (!subscribeMenu.contains(event.target)) setSubscribeOpen(false);
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") setSubscribeOpen(false);
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
  const previousButton = lightbox?.querySelector(".lightbox-previous");
  const nextButton = lightbox?.querySelector(".lightbox-next");
  const caption = lightbox?.querySelector(".lightbox-caption");

  if (lightbox && lightboxImage && previousButton && nextButton && caption && "showModal" in lightbox) {
    const triggers = Array.from(document.querySelectorAll(".lightbox-trigger"));
    let currentIndex = 0;

    const showPhoto = (index) => {
      currentIndex = (index + triggers.length) % triggers.length;
      const trigger = triggers[currentIndex];
      lightboxImage.src = trigger.href;
      lightboxImage.alt = trigger.dataset.lightboxAlt;
      caption.textContent = trigger.dataset.lightboxTitle;
    };

    previousButton.hidden = triggers.length < 2;
    nextButton.hidden = triggers.length < 2;

    triggers.forEach((trigger, index) => {
      trigger.addEventListener("click", (event) => {
        event.preventDefault();
        showPhoto(index);
        lightbox.showModal();
      });
    });

    previousButton.addEventListener("click", () => showPhoto(currentIndex - 1));
    nextButton.addEventListener("click", () => showPhoto(currentIndex + 1));
    lightbox.addEventListener("keydown", (event) => {
      if (triggers.length < 2) return;
      if (event.key === "ArrowLeft") {
        event.preventDefault();
        showPhoto(currentIndex - 1);
      } else if (event.key === "ArrowRight") {
        event.preventDefault();
        showPhoto(currentIndex + 1);
      }
    });

    closeButton.addEventListener("click", () => lightbox.close());
    lightbox.addEventListener("click", (event) => {
      if (event.target === lightbox) lightbox.close();
    });
  }

  const backToTop = document.querySelector(".back-to-top");

  if (backToTop && calendar) {
    const updateBackToTop = () => {
      const boundary = calendar.offsetParent ? calendar : document.querySelector(".site-header");
      backToTop.hidden = boundary.getBoundingClientRect().bottom >= 0;
    };

    window.addEventListener("scroll", updateBackToTop, { passive: true });
    window.addEventListener("resize", updateBackToTop);
    backToTop.addEventListener("click", () => {
      const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      window.scrollTo({ top: 0, behavior: reducedMotion ? "auto" : "smooth" });
    });
    updateBackToTop();
  }
})();
