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
    return;
  }

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
})();
