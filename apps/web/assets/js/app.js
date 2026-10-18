import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { persistBrowserPreference } from "./browser_preferences.mjs";

const COLORS = ["yellow", "blue", "red", "orange", "purple"];

const Board = {
  mounted() {
    this.drag = null;
    this.drawing = null;
    this.arrowStart = null;
    this.suppressClick = false;
    this.pendingMove = null;
    this.pendingShapes = [];
    this.pendingTimer = null;
    this.longPress = null;

    // Mobile app shell: the board fills the space left by the chrome, so it
    // scales with the viewport and the panel size.
    this.fitBoard = () => {
      const zone = this.el.closest("[data-board-zone]");
      if (!zone || !window.matchMedia("(max-width: 859.98px)").matches) {
        this.el.style.width = "";
        this.el.style.height = "";
        return;
      }
      const size = Math.floor(Math.min(zone.clientWidth, zone.clientHeight));
      if (size > 0) {
        this.el.style.width = `${size}px`;
        this.el.style.height = `${size}px`;
      }
    };

    const boardZone = this.el.closest("[data-board-zone]");
    if (boardZone) {
      this.boardFitObserver = new ResizeObserver(this.fitBoard);
      this.boardFitObserver.observe(boardZone);
      this.fitBoard();
      requestAnimationFrame(() => this.fitBoard());
      window.addEventListener("resize", this.fitBoard);
    }

    this.pointerDown = (event) => {
      const square = this.squareAt(event.target);
      if (square === null) return;

      this.arrowStart = null;
      this.removeDrawingPreview();

      if (event.button === 2) {
        event.preventDefault();
        const color = this.annotationColor(event);
        this.drawing = {
          from: square,
          color,
          x: event.clientX,
          y: event.clientY,
          moved: false,
        };
        return;
      }

      if (event.button !== 0) return;

      if (event.pointerType !== "mouse") {
        this.beginLongPress(square, event);
      }

      if (!event.target.closest("[data-piece]")) return;
      this.drag = {
        from: square,
        x: event.clientX,
        y: event.clientY,
        moved: false,
      };
    };

    this.pointerMove = (event) => {
      if (this.longPress) {
        const travelled =
          Math.abs(event.clientX - this.longPress.x) +
          Math.abs(event.clientY - this.longPress.y);
        if (travelled > 10) this.cancelLongPress();
      }

      if (this.drawing) {
        if (
          !this.drawing.moved &&
          Math.abs(event.clientX - this.drawing.x) +
            Math.abs(event.clientY - this.drawing.y) >
            6
        ) {
          this.drawing.moved = true;
          this.el.setPointerCapture?.(event.pointerId);
        }
        if (this.drawing.moved)
          this.renderDrawingPreview(event.clientX, event.clientY);
        return;
      }

      if (!this.drag) return;
      if (
        !this.drag.moved &&
        Math.abs(event.clientX - this.drag.x) +
          Math.abs(event.clientY - this.drag.y) >
          6
      ) {
        this.drag.moved = true;
        this.cancelLongPress();
        this.el.dataset.dragging = "true";
        this.el.setPointerCapture?.(event.pointerId);
        this.startDragPreview(this.drag.from, event.clientX, event.clientY);
      }
      if (this.drag.moved) this.renderDragPreview(event.clientX, event.clientY);
    };

    this.pointerUp = (event) => {
      this.cancelLongPress();
      const target = document.elementFromPoint(event.clientX, event.clientY);
      const square = this.squareAt(target);

      if (this.drawing) {
        const { from, color } = this.drawing;
        this.drawing = null;
        if (square === from) {
          this.pushAnnotation({ type: "square", square, color });
        } else if (square !== null) {
          this.pushAnnotation({ type: "arrow", from, to: square, color });
        }
        this.removeDrawingPreview();
        return;
      }

      if (!this.drag) return;
      const { from, moved } = this.drag;
      this.drag = null;
      delete this.el.dataset.dragging;
      if (moved && square !== null && square !== from) {
        this.suppressClick = true;
        window.setTimeout(() => {
          this.suppressClick = false;
        }, 0);
        this.beginPendingMove(from, square);
        this.pushEvent("board-move", { from, to: square }, () =>
          this.clearPendingMove(),
        );
      } else {
        this.clearDragPreview();
      }
    };

    this.suppressDraggedClick = (event) => {
      if (!this.suppressClick) return;
      event.preventDefault();
      event.stopPropagation();
      this.suppressClick = false;
    };

    this.pointerCancel = () => {
      this.cancelLongPress();
      this.drag = null;
      this.drawing = null;
      this.arrowStart = null;
      this.removeDrawingPreview();
      this.clearDragPreview();
      delete this.el.dataset.dragging;
    };

    this.keyDown = (event) => {
      // An open dialog owns the keyboard; the key still bubbles to the
      // document handler, which closes the dialog on Escape.
      if (document.querySelector("[aria-modal='true']")) return;

      if (event.key === "Escape") {
        if (this.arrowStart !== null || this.drawing) {
          this.cancelArrow();
          return;
        }
        this.clearPendingShapes();
        this.pushEvent("clear-annotations", {});
        return;
      }

      if (/^[1-5]$/.test(event.key)) {
        this.pushEvent("annotation-color", {
          color: COLORS[Number(event.key) - 1],
        });
        return;
      }

      if (event.key.toLowerCase() === "c") {
        this.clearPendingShapes();
        this.pushEvent("clear-annotations", {});
        return;
      }

      const button = event.target.closest("[data-square]");
      if (!button) return;
      const current = Number(button.dataset.square);

      if (event.key.toLowerCase() === "h") {
        event.preventDefault();
        this.pushAnnotation({
          type: "square",
          square: current,
          color: this.el.dataset.annotationColor || "blue",
        });
        return;
      }

      if (event.key.toLowerCase() === "a") {
        event.preventDefault();
        this.toggleArrow(current);
        return;
      }

      if (
        this.arrowStart !== null &&
        (event.key === "Enter" || event.key === " ")
      ) {
        event.preventDefault();
        this.finishArrow(current);
        return;
      }

      // Shift+arrows step the mainline (handled at the document level)
      if (event.shiftKey) return;

      const offsets = {
        ArrowLeft: this.el.dataset.orientation === "black" ? 1 : -1,
        ArrowRight: this.el.dataset.orientation === "black" ? -1 : 1,
        ArrowUp: this.el.dataset.orientation === "black" ? -8 : 8,
        ArrowDown: this.el.dataset.orientation === "black" ? 8 : -8,
      };
      const offset = offsets[event.key];
      if (offset === undefined) return;
      event.preventDefault();
      const file = current % 8;
      const rank = Math.floor(current / 8);
      const nextFile = file + (offset === -1 || offset === 1 ? offset : 0);
      const nextRank = rank + (offset === -8 || offset === 8 ? offset / 8 : 0);
      if (nextFile < 0 || nextFile > 7 || nextRank < 0 || nextRank > 7) return;
      const next = nextRank * 8 + nextFile;
      this.el.querySelector(`[data-square="${next}"]`)?.focus();
      this.pushEvent("board-cursor", { square: next });
      if (this.arrowStart !== null) {
        requestAnimationFrame(() => this.renderKeyboardArrowPreview());
      }
    };

    // Click-to-move: hold the piece on the target as soon as a legal target is
    // clicked, so a slow (cross-region) round trip doesn't show it jump back.
    this.clickToMove = (event) => {
      if (this.pendingMove) return;
      const squareEl = event.target.closest("[data-square]");
      if (!squareEl) return;
      // `aria-pressed` is rendered as an empty boolean attribute when selected
      const selected = this.el.querySelector("[data-square][aria-pressed]");
      if (!selected) return;
      const from = Number(selected.dataset.square);
      const to = Number(squareEl.dataset.square);
      if (to === from) return;
      const legalTarget =
        squareEl.querySelector('[class*="board-legal"]') !== null ||
        squareEl.classList.contains("ring-4");
      if (!legalTarget) return;
      this.beginPendingMove(from, to);
    };
    this.el.addEventListener("click", this.clickToMove, true);

    this.clearPending = () => this.clearPendingShapes();
    document.addEventListener("openchesslab:clear-annotations", this.clearPending);

    this.contextMenu = (event) => event.preventDefault();
    this.el.addEventListener("pointerdown", this.pointerDown);
    this.el.addEventListener("pointermove", this.pointerMove);
    this.el.addEventListener("pointerup", this.pointerUp);
    this.el.addEventListener("pointercancel", this.pointerCancel);
    this.el.addEventListener("click", this.suppressDraggedClick, true);
    this.el.addEventListener("keydown", this.keyDown);
    this.el.addEventListener("contextmenu", this.contextMenu);
  },

  destroyed() {
    this.cancelLongPress();
    this.clearArrowState();
    this.boardFitObserver?.disconnect();
    if (this.fitBoard) window.removeEventListener("resize", this.fitBoard);
    document.removeEventListener("openchesslab:clear-annotations", this.clearPending);
    this.clearPendingShapes();
    this.el.removeEventListener("click", this.clickToMove, true);
    this.el.removeEventListener("pointerdown", this.pointerDown);
    this.el.removeEventListener("pointermove", this.pointerMove);
    this.el.removeEventListener("pointerup", this.pointerUp);
    this.el.removeEventListener("pointercancel", this.pointerCancel);
    this.el.removeEventListener("click", this.suppressDraggedClick, true);
    this.el.removeEventListener("keydown", this.keyDown);
    this.el.removeEventListener("contextmenu", this.contextMenu);
    this.removeDrawingPreview();
    this.clearDragPreview();
  },

  updated() {
    this.fitBoard?.();

    // LiveView patches re-render the squares, which drops the client-side
    // arrow-draft marker; restore it (or clean it up) after each patch.
    if (this.arrowStart !== null) {
      this.showArrowState(this.arrowStart);
    } else {
      this.clearArrowState();
    }

    this.confirmPendingMove();
    this.reconcilePendingShapes();
    this.renderKeyboardArrowPreview();
  },

  // Touch/pen have no right-click, so a long press starts the same drawing
  // gesture (single square = highlight, drag = arrow).
  beginLongPress(square, event) {
    this.cancelLongPress();
    const color = this.el.dataset.annotationColor || "blue";
    const timer = window.setTimeout(() => {
      this.longPress = null;
      this.drag = null;
      delete this.el.dataset.dragging;
      this.clearDragPreview();
      this.drawing = {
        from: square,
        color,
        x: event.clientX,
        y: event.clientY,
        moved: false,
      };
      navigator.vibrate?.(10);
    }, 350);
    this.longPress = { square, x: event.clientX, y: event.clientY, timer };
  },

  cancelLongPress() {
    if (this.longPress) {
      window.clearTimeout(this.longPress.timer);
      this.longPress = null;
    }
  },

  // Keyboard arrows: A starts at the focused square, A again (or Enter) finishes
  // at the new square, A on the same square cancels.
  toggleArrow(square) {
    if (this.arrowStart === null) {
      this.arrowStart = square;
      this.showArrowState(square);
      this.renderKeyboardArrowPreview();
      return;
    }

    if (this.arrowStart === square) {
      this.cancelArrow();
      return;
    }

    this.finishArrow(square);
  },

  finishArrow(square) {
    const from = this.arrowStart;

    // push first: the optimistic shape is cloned from the live preview
    if (from !== null && square !== null && from !== square) {
      this.pushAnnotation({
        type: "arrow",
        from,
        to: square,
        color: this.el.dataset.annotationColor || "blue",
      });
    }

    this.cancelArrow();
  },

  cancelArrow() {
    this.arrowStart = null;
    this.clearArrowState();
    this.removeDrawingPreview();
  },

  showArrowState(square) {
    document.body.dataset.boardArrow = "armed";

    this.el
      .querySelectorAll("[data-arrow-start]")
      .forEach((el) => delete el.dataset.arrowStart);
    this.el
      .querySelector(`[data-square="${square}"]`)
      ?.setAttribute("data-arrow-start", "true");

    const hint = document.querySelector("[data-arrow-hint] [data-arrow-from]");
    if (hint) hint.textContent = this.squareName(square);
  },

  clearArrowState() {
    delete document.body.dataset.boardArrow;
    this.el
      .querySelectorAll("[data-arrow-start]")
      .forEach((el) => delete el.dataset.arrowStart);
  },

  squareName(square) {
    return "abcdefgh"[square % 8] + (Math.floor(square / 8) + 1);
  },

  squareAt(target) {
    const square = target?.closest?.("[data-square]")?.dataset.square;
    return square === undefined ? null : Number(square);
  },

  annotationColor(event) {
    const current = this.el.dataset.annotationColor || "blue";
    const index = COLORS.indexOf(current);
    if (event.altKey) return COLORS[(index + 1) % COLORS.length];
    if (event.shiftKey)
      return COLORS[(index + COLORS.length - 1) % COLORS.length];
    return current;
  },

  renderDrawingPreview(clientX, clientY) {
    if (!this.drawing) return;
    const targetSquare = this.squareAt(
      document.elementFromPoint(clientX, clientY),
    );

    if (targetSquare === null || targetSquare === this.drawing.from) {
      this.removeDrawingPreview();
      return;
    }

    this.renderArrowPreview(
      this.drawing.from,
      targetSquare,
      this.drawing.color,
    );
  },

  renderKeyboardArrowPreview() {
    if (this.arrowStart === null || this.drawing) return;
    const targetSquare = this.squareAt(document.activeElement);

    if (targetSquare === null || targetSquare === this.arrowStart) {
      this.removeDrawingPreview();
      return;
    }

    this.renderArrowPreview(
      this.arrowStart,
      targetSquare,
      this.el.dataset.annotationColor || "blue",
    );
  },

  renderArrowPreview(from, to, colorName) {
    const grid = this.el.querySelector("[data-board-grid]");
    const fromSquare = this.el.querySelector(`[data-square="${from}"]`);
    const toSquare = this.el.querySelector(`[data-square="${to}"]`);
    if (!grid || !fromSquare || !toSquare || from === to) {
      this.removeDrawingPreview();
      return;
    }

    let svg = this.el.querySelector("[data-drawing-preview]");
    if (!svg) {
      const namespace = "http://www.w3.org/2000/svg";
      svg = document.createElementNS(namespace, "svg");
      svg.dataset.drawingPreview = "true";
      svg.setAttribute("viewBox", "0 0 800 800");
      svg.setAttribute("preserveAspectRatio", "none");
      Object.assign(svg.style, {
        position: "absolute",
        inset: "0",
        width: "100%",
        height: "100%",
        overflow: "visible",
        pointerEvents: "none",
        zIndex: "30",
      });
      const line = document.createElementNS(namespace, "line");
      line.dataset.previewLine = "true";
      line.setAttribute("stroke-width", "10");
      line.setAttribute("stroke-linecap", "round");
      line.setAttribute("opacity", ".88");
      const head = document.createElementNS(namespace, "polygon");
      head.dataset.previewHead = "true";
      head.setAttribute("opacity", ".88");
      svg.append(line, head);
      grid.append(svg);
    }

    const gridRect = grid.getBoundingClientRect();
    const startRect = fromSquare.getBoundingClientRect();
    const x1 =
      ((startRect.left + startRect.width / 2 - gridRect.left) /
        gridRect.width) *
      800;
    const y1 =
      ((startRect.top + startRect.height / 2 - gridRect.top) /
        gridRect.height) *
      800;
    const endRect = toSquare.getBoundingClientRect();
    const x2 =
      ((endRect.left + endRect.width / 2 - gridRect.left) / gridRect.width) *
      800;
    const y2 =
      ((endRect.top + endRect.height / 2 - gridRect.top) / gridRect.height) *
      800;
    const color = this.shapeColor(colorName);
    const line = svg.querySelector("[data-preview-line]");
    const head = svg.querySelector("[data-preview-head]");
    line.setAttribute("x1", x1);
    line.setAttribute("y1", y1);
    line.setAttribute("x2", x2);
    line.setAttribute("y2", y2);
    line.setAttribute("stroke", color);
    head.setAttribute("fill", color);

    const angle = Math.atan2(y2 - y1, x2 - x1);
    const length = 30;
    const halfWidth = 17;
    const baseX = x2 - Math.cos(angle) * length;
    const baseY = y2 - Math.sin(angle) * length;
    const leftX = baseX + Math.sin(angle) * halfWidth;
    const leftY = baseY - Math.cos(angle) * halfWidth;
    const rightX = baseX - Math.sin(angle) * halfWidth;
    const rightY = baseY + Math.cos(angle) * halfWidth;
    head.setAttribute(
      "points",
      `${x2},${y2} ${leftX},${leftY} ${rightX},${rightY}`,
    );
  },

  startDragPreview(from, clientX, clientY) {
    const grid = this.el.querySelector("[data-board-grid]");
    const source = this.el.querySelector(`[data-square="${from}"]`);
    const piece = source?.querySelector("[data-piece]");
    if (!grid || !source || !piece) return;

    source.dataset.dragSource = "true";
    grid.querySelector("[data-drag-ghost]")?.remove();

    const ghost = document.createElement("span");
    ghost.dataset.dragGhost = "true";
    Object.assign(ghost.style, {
      position: "absolute",
      width: "12.5%",
      height: "12.5%",
      display: "grid",
      placeItems: "center",
      pointerEvents: "none",
      transform: "translate(-50%, -50%)",
      zIndex: "40",
    });
    const pieceGhost = piece.cloneNode(true);
    pieceGhost.setAttribute("aria-hidden", "true");
    ghost.append(pieceGhost);
    grid.append(ghost);

    this.renderDragPreview(clientX, clientY);
  },

  renderDragPreview(clientX, clientY) {
    const grid = this.el.querySelector("[data-board-grid]");
    const ghost = grid?.querySelector("[data-drag-ghost]");
    if (!grid || !ghost) return;
    const rect = grid.getBoundingClientRect();
    ghost.style.left = `${clientX - rect.left}px`;
    ghost.style.top = `${clientY - rect.top}px`;
  },

  clearDragPreview() {
    window.clearTimeout(this.pendingTimer);
    this.pendingTimer = null;
    this.el.querySelector("[data-drag-ghost]")?.remove();
    this.el
      .querySelector("[data-drag-source]")
      ?.removeAttribute("data-drag-source");
  },

  // Keep the piece visually on the target square until the server confirms the
  // move. Cross-region round trips can take seconds, so the hold is only
  // cleared by the confirmation (or a long safety timeout) — never by a short
  // timer that made the piece snap back and forth.
  beginPendingMove(from, to) {
    if (!this.ensureGhost(from, to)) return;

    this.pendingMove = { from, to };
    window.clearTimeout(this.pendingTimer);
    this.pendingTimer = window.setTimeout(() => this.clearPendingMove(), 12000);
  },

  ensureGhost(from, to) {
    const grid = this.el.querySelector("[data-board-grid]");
    const source = this.el.querySelector(`[data-square="${from}"]`);
    const target = this.el.querySelector(`[data-square="${to}"]`);
    if (!grid || !source || !target) return false;

    let ghost = grid.querySelector("[data-drag-ghost]");
    if (!ghost) {
      const piece = source.querySelector("[data-piece]");
      if (!piece) return false;
      ghost = document.createElement("span");
      ghost.dataset.dragGhost = "true";
      Object.assign(ghost.style, {
        position: "absolute",
        width: "12.5%",
        height: "12.5%",
        display: "grid",
        placeItems: "center",
        pointerEvents: "none",
        transform: "translate(-50%, -50%)",
        zIndex: "40",
      });
      const clone = piece.cloneNode(true);
      clone.setAttribute("aria-hidden", "true");
      ghost.append(clone);
      grid.append(ghost);
    }

    source.dataset.dragSource = "true";
    this.snapGhost(ghost, grid, target);
    ghost.dataset.dragPending = "true";
    return true;
  },

  snapGhost(ghost, grid, target) {
    const gridRect = grid.getBoundingClientRect();
    const targetRect = target.getBoundingClientRect();
    ghost.style.left = `${targetRect.left - gridRect.left + targetRect.width / 2}px`;
    ghost.style.top = `${targetRect.top - gridRect.top + targetRect.height / 2}px`;
  },

  confirmPendingMove() {
    if (!this.pendingMove) return;
    const { from, to } = this.pendingMove;
    const source = this.el.querySelector(`[data-square="${from}"]`);
    const target = this.el.querySelector(`[data-square="${to}"]`);

    if (target?.querySelector("[data-piece]") && !source?.querySelector("[data-piece]")) {
      this.clearPendingMove();
      return;
    }

    // Patches can drop the ghost; put it back so the piece stays on the target.
    this.ensureGhost(from, to);
  },

  clearPendingMove() {
    this.pendingMove = null;
    this.clearDragPreview();
  },

  // Annotations: keep the local shape until the server renders it, so arrows
  // and highlights don't blink out during the round trip.
  pushAnnotation(payload) {
    const key =
      payload.type === "arrow"
        ? `arrow-${payload.from}-${payload.to}-${payload.color}`
        : `square-${payload.square}-${payload.color}`;

    // If the server already renders this shape, this is a removal: don't add
    // an optimistic copy.
    if (!this.el.querySelector(`[data-shape-key="${key}"]`)) {
      this.addPendingShape(key, payload);
    }

    this.pushEvent("board-annotation", payload);
  },

  addPendingShape(key, payload) {
    if (this.pendingShapes.some((shape) => shape.key === key)) return;
    const grid = this.el.querySelector("[data-board-grid]");
    if (!grid) return;

    let el = null;

    if (payload.type === "arrow") {
      const preview = this.el.querySelector("[data-drawing-preview]");
      if (!preview) return;
      el = preview.cloneNode(true);
      el.removeAttribute("data-drawing-preview");
    } else {
      const file = payload.square % 8;
      const rank = Math.floor(payload.square / 8);
      const black = this.el.dataset.orientation === "black";
      el = document.createElement("div");
      Object.assign(el.style, {
        position: "absolute",
        left: `${(black ? 7 - file : file) * 12.5}%`,
        top: `${(black ? rank : 7 - rank) * 12.5}%`,
        width: "12.5%",
        height: "12.5%",
        border: `5px solid ${this.shapeColor(payload.color)}`,
        pointerEvents: "none",
        zIndex: "10",
        boxSizing: "border-box",
      });
    }

    el.dataset.pendingShape = key;
    grid.append(el);
    this.pendingShapes.push({
      key,
      el,
      timer: window.setTimeout(() => this.clearPendingShape(key), 8000),
    });
  },

  clearPendingShape(key) {
    const index = this.pendingShapes.findIndex((shape) => shape.key === key);
    if (index === -1) return;
    const [shape] = this.pendingShapes.splice(index, 1);
    window.clearTimeout(shape.timer);

    // LiveView's morph can reuse our optimistic node as the real server shape
    // (it then carries data-shape-key and lost the pending marker). Only
    // remove the node while it is still the pending copy.
    if (shape.el.dataset.pendingShape) shape.el.remove();
  },

  clearPendingShapes() {
    for (const shape of [...this.pendingShapes]) this.clearPendingShape(shape.key);
  },

  reconcilePendingShapes() {
    for (const shape of [...this.pendingShapes]) {
      if (this.el.querySelector(`[data-shape-key="${shape.key}"]`)) {
        this.clearPendingShape(shape.key);
      } else if (!shape.el.isConnected) {
        this.el.querySelector("[data-board-grid]")?.append(shape.el);
      }
    }
  },

  removeDrawingPreview() {
    this.el.querySelector("[data-drawing-preview]")?.remove();
  },

  shapeColor(color) {
    return (
      {
        yellow: "#f2c200",
        blue: "#3b6fe0",
        red: "#d6453d",
        orange: "#e08a1e",
        purple: "#8b5cf6",
      }[color] || "#3b6fe0"
    );
  },
};

const AnalysisTabs = {
  mounted() {
    // Middle-click (mouse wheel) closes a tab: swallow the browser's
    // autoscroll and route it through the same confirmation as the × button.
    this.onMouseDown = (event) => {
      if (event.button === 1 && event.target.closest("[data-analysis-id]")) {
        event.preventDefault();
      }
    };
    this.onAuxClick = (event) => {
      if (event.button !== 1) return;
      const tab = event.target.closest("[data-analysis-id]");
      if (!tab || !this.el.contains(tab)) return;
      event.preventDefault();
      this.pushEvent("request-remove-analysis", { id: tab.dataset.analysisId });
    };
    this.el.addEventListener("mousedown", this.onMouseDown);
    this.el.addEventListener("auxclick", this.onAuxClick);
    this.scrollActiveIntoView();
  },

  updated() {
    this.scrollActiveIntoView();
  },

  destroyed() {
    this.el.removeEventListener("mousedown", this.onMouseDown);
    this.el.removeEventListener("auxclick", this.onAuxClick);
  },

  scrollActiveIntoView() {
    const active = this.el.querySelector('[aria-current="true"]');
    if (active) {
      active.scrollIntoView({ block: "nearest", inline: "nearest" });
    }
  },
};

const ScrollLog = {
  mounted() {
    this.scrollToBottom = () => {
      this.el.scrollTop = this.el.scrollHeight;
    };

    // The chat panel can start hidden (mobile tab) with a zero-height log, so
    // jump to the newest message as soon as it becomes visible.
    this.lastHeight = this.el.clientHeight;
    this.observer = new ResizeObserver(() => {
      const height = this.el.clientHeight;
      if (height > 0 && this.lastHeight === 0) {
        this.stick = true;
        this.scrollToBottom();
      }
      this.lastHeight = height;
    });
    this.observer.observe(this.el);

    // Track whether the reader is pinned to the bottom *before* new messages
    // arrive; measuring afterwards fails for messages taller than the threshold.
    this.stick = true;
    this.onScroll = () => {
      const remaining =
        this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight;
      this.stick = remaining < 48;
    };
    this.el.addEventListener("scroll", this.onScroll);

    this.scrollToBottom();
  },

  updated() {
    const last = this.el.querySelector("article:last-of-type");
    const mine = last && last.classList.contains("self-end");

    // always follow your own message; follow others when already at the bottom
    if (mine || this.stick) this.scrollToBottom();
  },

  destroyed() {
    this.observer?.disconnect();
    this.el.removeEventListener("scroll", this.onScroll);
  },
};

// Spotlights the current tour step's target: dims everything else behind a
// ring drawn over the target and places the explanation card beside it. Steps
// without a visible anchor fall back to a centered card.
const ImportMasterCheckbox = {
  // The master checkbox shows a dash while part of the tray is selected.
  mounted() {
    this.sync();
  },
  updated() {
    this.sync();
  },
  sync() {
    this.el.indeterminate = this.el.dataset.indeterminate === "true";
  },
};

const GuidedTour = {
  mounted() {
    this.reposition = () => this.position();
    window.addEventListener("resize", this.reposition);
    window.addEventListener("scroll", this.reposition, true);
    this.position();
  },
  updated() {
    this.position();
  },
  destroyed() {
    window.removeEventListener("resize", this.reposition);
    window.removeEventListener("scroll", this.reposition, true);
  },
  position() {
    const backdrop = this.el.querySelector("[data-tour-backdrop]");
    const ring = this.el.querySelector("[data-tour-ring]");
    const card = this.el.querySelector("[data-tour-card]");
    const target = this.el.dataset.tourTarget
      ? document.querySelector(`[data-tour="${this.el.dataset.tourTarget}"]`)
      : null;
    const rect = target?.getBoundingClientRect();

    if (!rect || (rect.width === 0 && rect.height === 0)) {
      backdrop.style.clipPath = "none";
      ring.style.display = "none";
      card.style.top = "50%";
      card.style.left = "50%";
      // Tailwind v4 translates via the CSS `translate` property, so reset both.
      card.style.transform = "translate(-50%, -50%)";
      card.style.translate = "-50% -50%";
      return;
    }

    target.scrollIntoView({ block: "nearest", inline: "nearest" });
    const r = target.getBoundingClientRect();
    const pad = 6;
    ring.style.display = "block";
    ring.style.top = `${r.top - pad}px`;
    ring.style.left = `${r.left - pad}px`;
    ring.style.width = `${r.width + pad * 2}px`;
    ring.style.height = `${r.height + pad * 2}px`;
    // Cut a hole in the blurred backdrop so the highlighted element stays crisp.
    const hx = r.left - pad;
    const hy = r.top - pad;
    const hw = r.width + pad * 2;
    const hh = r.height + pad * 2;
    backdrop.style.clipPath = `polygon(evenodd, 0 0, 100% 0, 100% 100%, 0 100%, 0 0, ${hx}px ${hy}px, ${hx + hw}px ${hy}px, ${hx + hw}px ${hy + hh}px, ${hx}px ${hy + hh}px, ${hx}px ${hy}px)`;

    const m = 12;
    const cw = card.offsetWidth;
    const ch = card.offsetHeight;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    let top;
    let left;

    if (r.right + m + cw <= vw) {
      left = r.right + m;
      top = r.top + r.height / 2 - ch / 2;
    } else if (r.left - m - cw >= 0) {
      left = r.left - m - cw;
      top = r.top + r.height / 2 - ch / 2;
    } else if (r.bottom + m + ch <= vh) {
      top = r.bottom + m;
      left = r.left + r.width / 2 - cw / 2;
    } else {
      top = r.top - m - ch;
      left = r.left + r.width / 2 - cw / 2;
    }

    card.style.top = `${Math.max(m, Math.min(top, vh - ch - m))}px`;
    card.style.left = `${Math.max(m, Math.min(left, vw - cw - m))}px`;
    card.style.transform = "none";
    card.style.translate = "none";
  },
};

const EvalBar = {
  mounted() {
    this.findBoard = () =>
      this.el
        .closest("[data-tour='board']")
        ?.querySelector("#chess-board [data-board-grid]");

    this.syncHeight = () => {
      const board = this.findBoard();

      if (board !== this.board) {
        this.resizeObserver?.disconnect();
        this.board = board;
        if (this.board) this.resizeObserver?.observe(this.board);
      }

      if (this.board) {
        this.el.style.height = `${this.board.getBoundingClientRect().height}px`;
      }
    };

    this.resizeObserver = new ResizeObserver(this.syncHeight);
    this.syncHeight();
  },

  updated() {
    this.syncHeight();
  },

  destroyed() {
    this.resizeObserver?.disconnect();
  },
};

const PaletteDrag = {
  mounted() {
    this.ghost = null;
    this.drag = null;
    this.grab = null;

    this.onPointerDown = (event) => {
      const button = event.target.closest("[data-piece-code]");
      if (!button || event.button !== 0) return;
      const rect = button.getBoundingClientRect();
      this.drag = {
        piece: button.dataset.pieceCode,
        x: event.clientX,
        y: event.clientY,
        started: false,
      };
      this.grab = { w: rect.width, h: rect.height, html: button.innerHTML };
      button.setPointerCapture?.(event.pointerId);
    };

    this.onPointerMove = (event) => {
      if (!this.drag) return;
      if (!this.drag.started) {
        const travelled =
          Math.abs(event.clientX - this.drag.x) +
          Math.abs(event.clientY - this.drag.y);
        if (travelled < 6) return;
        this.drag.started = true;
        this.showGhost();
      }
      this.positionGhost(event.clientX, event.clientY);
    };

    this.onPointerUp = (event) => {
      if (!this.drag) return;
      const drag = this.drag;
      this.drag = null;
      this.removeGhost();
      if (!drag.started) return; // plain tap: the button's phx-click arms the piece

      const squareButton = document
        .elementFromPoint(event.clientX, event.clientY)
        ?.closest("[data-square]");
      if (!squareButton) return;

      const board = squareButton.closest("#setup-board, #chess-board");
      const name =
        board && board.id === "setup-board"
          ? "setup-palette-drop"
          : "palette-drop";
      this.pushEvent(name, {
        piece: drag.piece,
        square: squareButton.dataset.square,
      });
    };

    this.onPointerCancel = () => {
      this.drag = null;
      this.removeGhost();
    };

    this.el.addEventListener("pointerdown", this.onPointerDown);
    this.el.addEventListener("pointermove", this.onPointerMove);
    this.el.addEventListener("pointerup", this.onPointerUp);
    this.el.addEventListener("pointercancel", this.onPointerCancel);
  },

  destroyed() {
    this.el.removeEventListener("pointerdown", this.onPointerDown);
    this.el.removeEventListener("pointermove", this.onPointerMove);
    this.el.removeEventListener("pointerup", this.onPointerUp);
    this.el.removeEventListener("pointercancel", this.onPointerCancel);
    this.removeGhost();
  },

  showGhost() {
    if (this.ghost) return;
    const ghost = document.createElement("div");
    ghost.dataset.paletteGhost = "true";
    Object.assign(ghost.style, {
      position: "fixed",
      width: `${this.grab.w}px`,
      height: `${this.grab.h}px`,
      display: "grid",
      placeItems: "center",
      pointerEvents: "none",
      zIndex: "80",
      opacity: ".85",
    });
    ghost.innerHTML = this.grab.html;
    document.body.append(ghost);
    this.ghost = ghost;
  },

  positionGhost(clientX, clientY) {
    if (!this.ghost) return;
    this.ghost.style.left = `${clientX - this.grab.w / 2}px`;
    this.ghost.style.top = `${clientY - this.grab.h / 2}px`;
  },

  removeGhost() {
    this.ghost?.remove();
    this.ghost = null;
  },
};

const MoveList = {
  mounted() {
    this.keepCurrentMoveVisible = () => {
      const current = this.el.querySelector('[aria-current="location"]');

      if (!current) {
        this.el.scrollTo?.({ top: 0 });
        return;
      }

      const listRect = this.el.getBoundingClientRect();
      const moveRect = current.getBoundingClientRect();

      if (moveRect.top < listRect.top) {
        this.el.scrollTop += moveRect.top - listRect.top;
      } else if (moveRect.bottom > listRect.bottom) {
        this.el.scrollTop += moveRect.bottom - listRect.bottom;
      }
    };

    // Roving tabindex is kept client-side: a phx-focus round trip on mousedown
    // patches the button mid-click and swallows the click event.
    this.setTabstop = (button) => {
      this.el.querySelectorAll("[data-move-path]").forEach((el) => {
        el.tabIndex = el === button ? 0 : -1;
      });
    };

    this.onFocusIn = (event) => {
      const button = event.target.closest?.("[data-move-path]");
      if (button && this.el.contains(button)) this.setTabstop(button);
    };

    this.el.addEventListener("focusin", this.onFocusIn);
    this.keepCurrentMoveVisible();
  },

  updated() {
    this.keepCurrentMoveVisible();

    const focused = document.activeElement;
    if (
      focused &&
      this.el.contains(focused) &&
      focused.hasAttribute?.("data-move-path")
    ) {
      this.setTabstop(focused);
    }
  },

  destroyed() {
    this.el.removeEventListener("focusin", this.onFocusIn);
  },
};

const AppUI = {
  mounted() {
    this.handleEvent("set-theme", ({ theme }) => {
      document.documentElement.dataset.theme = theme;
      this.el.dataset.theme = theme;
      persistBrowserPreference("theme", theme);
    });

    this.handleEvent("set-locale", ({ locale }) => {
      document.documentElement.lang = locale;
      persistBrowserPreference("locale", locale);
    });

    this.handleEvent("set-piece-set", ({ piece_set }) => {
      try {
        localStorage.setItem("openchesslab:piece-set", piece_set);
      } catch (_) {
        /* optional */
      }
    });

    this.handleEvent("set-annotation-color", ({ color }) => {

      try {
        localStorage.setItem("openchesslab:annotation-color", color);
      } catch (_) {
        /* optional */
      }
    });

    this.handleEvent("focus-move", ({ path }) => {
      const selector = path
        ? `[data-move-path="${path}"]`
        : `[data-move-path="0"]`;
      requestAnimationFrame(() => this.el.querySelector(selector)?.focus());
    });

    this.handleEvent("copy-text", async ({ text, notice }) => {
      try {
        const copyValue = text.startsWith("/")
          ? new URL(text, window.location.origin).toString()
          : text;
        await navigator.clipboard.writeText(copyValue);
        if (notice)
          this.pushEvent("clipboard-result", { success: true, notice });
      } catch (_) {
        this.pushEvent("clipboard-result", { success: false, notice: text });
      }
    });

    this.handleEvent("download-svg", ({ svg, filename }) => {
      const blob = new Blob([svg], { type: "image/svg+xml;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = filename || "openchesslab-position.svg";
      anchor.click();
      URL.revokeObjectURL(url);
    });

    let preferences = {};
    try {
      preferences = {
        theme: localStorage.getItem("openchesslab:theme"),
        locale: localStorage.getItem("openchesslab:locale"),
        piece_set: localStorage.getItem("openchesslab:piece-set"),
        annotation_color: localStorage.getItem("openchesslab:annotation-color"),
      };
    } catch (_) {
      /* optional */
    }
    if (["system", "light", "dark"].includes(preferences.theme)) {
      persistBrowserPreference("theme", preferences.theme);
      this.el.dataset.theme = preferences.theme;
      document.documentElement.dataset.theme = preferences.theme;
    }
    if (["en", "nl"].includes(preferences.locale)) {
      persistBrowserPreference("locale", preferences.locale);
      document.documentElement.lang = preferences.locale;
    }
    this.pushEvent("restore-preferences", preferences);

    this.keyDown = (event) => {
      const target = event.target;
      const typing = target?.matches?.(
        "input, textarea, select, [contenteditable='true']",
      );

      // Escape closes an open modal even while typing in one of its fields;
      // unlike letter shortcuts it is never input text.
      if (
        event.key === "Escape" &&
        !event.metaKey &&
        !event.ctrlKey &&
        !event.altKey
      ) {
        this.pushEvent("close-modal", {});
        return;
      }

      if (typing || event.metaKey || event.ctrlKey || event.altKey) return;

      // An open dialog owns the keyboard: the guided tour keeps its arrow
      // navigation, everything else is swallowed (Escape still closes it).
      if (document.querySelector("[aria-modal='true']")) {
        if (document.querySelector("[data-tour-dialog]")) {
          if (event.key === "ArrowLeft") {
            event.preventDefault();
            this.pushEvent("tour-back", {});
          } else if (event.key === "ArrowRight") {
            event.preventDefault();
            this.pushEvent("tour-next", {});
          }
        }
        return;
      }

      const moveButton = target?.closest?.("[data-move-path]");
      const board = target?.closest?.("[data-board]");

      // Shift+arrows step the mainline even while the board has focus, where
      // plain arrows move the square cursor.
      if (
        this.el.dataset.roomCode &&
        event.shiftKey &&
        (event.key === "ArrowLeft" || event.key === "ArrowRight")
      ) {
        event.preventDefault();
        this.pushEvent(
          event.key === "ArrowRight" ? "next-move" : "previous-move",
          {},
        );
        return;
      }

      if (
        moveButton &&
        ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)
      ) {
        event.preventDefault();
        this.pushEvent("move-tree-key", {
          path: moveButton.dataset.movePath,
          key: event.key,
        });
        return;
      }

      // Plain arrows step the mainline when neither the board nor the move tree
      // has focus (with the board focused they move the square cursor).
      if (
        this.el.dataset.roomCode &&
        !board &&
        !moveButton &&
        (event.key === "ArrowLeft" || event.key === "ArrowRight")
      ) {
        event.preventDefault();
        this.pushEvent(
          event.key === "ArrowRight" ? "next-move" : "previous-move",
          {},
        );
        return;
      }

      if (!board && this.el.dataset.roomCode && /^[1-5]$/.test(event.key)) {
        this.pushEvent("annotation-color", {
          color: COLORS[Number(event.key) - 1],
        });
        return;
      }

      if (event.key === "?") {
        event.preventDefault();
        this.pushEvent("open-shortcuts", {});
      } else if (event.key.toLowerCase() === "b" && this.el.dataset.roomCode) {
        event.preventDefault();
        this.el
          .querySelector("#chess-board [data-square][tabindex='0']")
          ?.focus();
      } else if (event.key.toLowerCase() === "m" && this.el.dataset.roomCode) {
        event.preventDefault();
        const moveTarget =
          this.el.querySelector("#move-list [tabindex='0']") ||
          this.el.querySelector("#move-list");
        moveTarget?.focus();
      } else if (event.key.toLowerCase() === "f" && this.el.dataset.roomCode) {
        this.pushEvent("toggle-orientation", {});
      } else if (event.key === "Home" && this.el.dataset.roomCode) {
        this.pushEvent("first-move", {});
      } else if (event.key === "End" && this.el.dataset.roomCode) {
        this.pushEvent("last-move", {});
      } else if (event.key.toLowerCase() === "e" && this.el.dataset.roomCode) {
        this.pushEvent("toggle-engine", {});
      }
    };
    document.addEventListener("keydown", this.keyDown);

    if (this.el.dataset.roomCode) {
      this.ping = window.setInterval(() => {
        const started = performance.now();
        this.pushEvent("latency-ping", {}, () => {
          const value = Math.max(0, Math.round(performance.now() - started));
          this.el
            .querySelector("[data-latency]")
            ?.replaceChildren(`${value} ms`);
        });
      }, 10000);
    }
  },

  destroyed() {
    if (this.ping) window.clearInterval(this.ping);
    document.removeEventListener("keydown", this.keyDown);
  },
};

// Runs the vendored Stockfish 19 WASM worker (single-threaded lite build, no
// COOP/COEP needed) against the position advertised via data attributes, and
// pushes throttled UCI info back to the LiveView. The worker only ever sees
// the FEN of the position on the board.
const EngineAnalysis = {
  mounted() {
    this.worker = null;
    this.ready = false;
    this.searching = false;
    this.searchKey = null;
    this.pendingGo = null;
    this.lines = new Map();
    this.best = null;
    this.flushTimer = null;
    this.fen = "";
    this.peekKey = null;
    this.peekTimer = null;

    // Hovering a move in the lines peeks at the position after that move.
    // Debounced so casual mouse movement does not spam the server.
    this.el.addEventListener("mouseover", (event) => {
      const button = event.target.closest("[data-peek-ply]");
      if (!button) return;

      const key = button.dataset.peekLine + ":" + button.dataset.peekPly;
      if (key === this.peekKey) return;
      this.peekKey = key;

      clearTimeout(this.peekTimer);
      this.peekTimer = setTimeout(() => {
        this.pushEvent("engine-peek", {
          line: button.dataset.peekLine,
          ply: button.dataset.peekPly,
        });
      }, 180);
    });

    this.el.addEventListener("mouseout", (event) => {
      const from = event.target.closest("[data-peek-ply]");
      if (!from) return;

      const to = event.relatedTarget && event.relatedTarget.closest("[data-peek-ply]");
      if (to) return;

      clearTimeout(this.peekTimer);
      this.peekKey = null;
      this.pushEvent("engine-peek-clear", {});
    });

    this.sync();
  },

  updated() {
    this.sync();
  },

  destroyed() {
    this.stopWorker();
  },

  sync() {
    // A running review owns the worker: it walks the mainline positions one
    // by one at a fixed depth and reports each back on bestmove.
    const reviewFen = this.el.dataset.reviewFen || "";
    const reviewPly = this.el.dataset.reviewPly || "";

    if (reviewFen && reviewPly !== "") {
      const key = ["review", reviewPly, reviewFen].join("|");
      if (key === this.searchKey) return;
      this.searchKey = key;
      this.reviewing = reviewPly;
      this.startSearch({ fen: reviewFen, depth: 12, multipv: 1 });
      return;
    }

    this.reviewing = null;

    const on = this.el.dataset.engineOn === "true";
    const fen = this.el.dataset.fen || "";
    const depth = parseInt(this.el.dataset.depth || "20", 10);
    const multipv = parseInt(this.el.dataset.multipv || "3", 10);

    if (!on || !fen) {
      this.searchKey = null;
      this.stopSearch();
      return;
    }

    const key = [fen, depth, multipv].join("|");
    if (key === this.searchKey) return;
    this.searchKey = key;

    // Coverage from the shared cache (or a just-finished compute) means no
    // local recompute: the panel already shows an evaluation of this position
    // at the requested depth AND at least as many lines.
    const cachedFen = this.el.dataset.cachedFen || "";
    const cachedDepth = parseInt(this.el.dataset.cachedDepth || "0", 10);
    const cachedMultipv = parseInt(this.el.dataset.cachedMultipv || "0", 10);

    if (cachedFen === fen && cachedDepth >= depth && cachedMultipv >= multipv) {
      this.stopSearch();
      return;
    }

    this.startSearch({ fen, depth, multipv });
  },

  ensureWorker() {
    if (this.worker) return true;

    try {
      this.worker = new Worker("/engine/stockfish.js");
    } catch (_) {
      this.fail();
      return false;
    }

    this.ready = false;
    this.worker.onerror = () => this.fail();
    this.worker.onmessage = (event) => this.handleLine(String(event.data));
    this.worker.postMessage("uci");
    return true;
  },

  handleLine(line) {
    if (line === "uciok") {
      this.worker.postMessage("isready");
      return;
    }

    if (line === "readyok") {
      this.ready = true;
      if (this.pendingGo) {
        const go = this.pendingGo;
        this.pendingGo = null;
        this.sendSearch(go);
      }
      return;
    }

    if (line.startsWith("info ")) {
      this.trackInfo(line);
      return;
    }

    if (line.startsWith("bestmove")) {
      // The final result always goes out: cancel any pending throttled flush
      // so the completed search is the one that gets persisted.
      if (this.flushTimer) {
        clearTimeout(this.flushTimer);
        this.flushTimer = null;
      }

      if (this.reviewing !== null && this.reviewing !== undefined) {
        // Terminal positions yield no info lines; report mate 0 (the side to
        // move is mated) so the review never stalls.
        const best = this.lines.get(1);
        const payload = { ply: this.reviewing };

        if (best) {
          if (best.scoreKind === "mate") payload.mate = best.score;
          else payload.cp = best.score;
        } else {
          payload.mate = 0;
        }

        this.pushEvent("engine-review-result", payload);
      } else {
        this.flush(true);
      }

      return;
    }
  },

  startSearch(search) {
    if (!this.ensureWorker()) return;
    this.stopSearch();

    if (this.ready) {
      this.sendSearch(search);
    } else {
      this.pendingGo = search;
    }
  },

  sendSearch({ fen, depth, multipv }) {
    this.worker.postMessage(`setoption name MultiPV value ${multipv}`);
    this.worker.postMessage(`position fen ${fen}`);
    this.worker.postMessage(`go depth ${depth}`);
    this.searching = true;
    this.fen = fen;
  },

  // Aborts the current search and clears buffered lines, but deliberately
  // keeps `searchKey`: it belongs to sync() and guards against restarts on
  // unrelated LiveView re-renders.
  stopSearch() {
    if (this.worker && this.searching) this.worker.postMessage("stop");
    this.searching = false;
    this.lines = new Map();
    this.best = null;

    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
  },

  trackInfo(line) {
    // info depth 14 seldepth 19 multipv 1 score cp 28 nodes 61234 nps 400000 time 153 pv e2e4 e7e5
    const match = line.match(
      /^info depth (\d+)(?:\s+\S+)*? multipv (\d+) score (cp|mate) (-?\d+)(?:\s+\S+)*? nodes (\d+)(?:\s+\S+)*? nps (\d+)(?:\s+\S+)*? pv (.*)$/,
    );
    if (!match) return;

    const [, depthS, multipvS, kind, valueS, nodesS, npsS, pv] = match;
    const depth = parseInt(depthS, 10);
    const multipv = parseInt(multipvS, 10);
    const previous = this.lines.get(multipv);
    if (previous && previous.depth > depth) return;

    this.lines.set(multipv, {
      multipv,
      depth,
      scoreKind: kind,
      score: parseInt(valueS, 10),
      pv: pv.trim(),
    });

    if (!this.best || depth >= this.best.depth) {
      this.best = { depth, nodes: parseInt(nodesS, 10), nps: parseInt(npsS, 10) };
    }

    this.flush(false);
  },

  flush(final) {
    if (this.flushTimer) return;

    this.flushTimer = setTimeout(
      () => {
        this.flushTimer = null;
        if (!this.lines.size) return;

        const lines = [...this.lines.values()]
          .sort((a, b) => a.multipv - b.multipv)
          .map((line) => ({
            multipv: line.multipv,
            ...(line.scoreKind === "mate"
              ? { score_mate: line.score }
              : { score_cp: line.score }),
            pv: line.pv,
          }));

        this.pushEvent("engine-update", {
          fen: this.fen,
          depth: this.best?.depth || 0,
          nodes: this.best?.nodes || 0,
          nps: this.best?.nps || 0,
          lines,
          final,
        });
      },
      final ? 0 : 250,
    );
  },

  fail() {
    this.stopWorker();
    this.pushEvent("engine-error", {});
  },

  stopWorker() {
    if (this.worker) {
      try {
        this.worker.terminate();
      } catch (_) {
        /* already gone */
      }
    }

    this.worker = null;
    this.ready = false;
    this.searching = false;
    this.searchKey = null;
    this.lines = new Map();
    this.best = null;
  },
};

const csrfToken = document.querySelector("meta[name='csrf-token']")?.content;
const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { AppUI, AnalysisTabs, Board, EngineAnalysis, EvalBar, GuidedTour, ImportMasterCheckbox, MoveList, PaletteDrag, ScrollLog },
  params: { _csrf_token: csrfToken },
});

liveSocket.connect();
window.liveSocket = liveSocket;
