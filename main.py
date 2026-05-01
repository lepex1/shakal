import tkinter as tk
import customtkinter as ctk
from tkinter import filedialog
from tkinterdnd2 import DND_FILES, TkinterDnD
from PIL import Image, ImageEnhance
import io
import os
import sys
import threading
import numpy as np
from moviepy.editor import VideoFileClip
from imageio_ffmpeg import get_ffmpeg_exe
import subprocess

# --- Настройки темы ---
ctk.set_appearance_mode("dark")

COLOR_ACTIVE = "#A0A0A5"
COLOR_INACTIVE = "#1A1A1B"
COLOR_VALUE_ACTIVE = "#FFFFFF"
COLOR_VALUE_INACTIVE = "#1A1A1B"
SLIDER_BG_ACTIVE = "#121214"
SLIDER_BG_INACTIVE = "#0D0D0E"
SLIDER_PROGRESS_ACTIVE = "#3B82F6"
SLIDER_PROGRESS_INACTIVE = "#1A1A1B"
SLIDER_BUTTON_ACTIVE = "#FFFFFF"
SLIDER_BUTTON_INACTIVE = "#1A1A1B"

class Shakal(TkinterDnD.Tk):
    def __init__(self):
        super().__init__()
        self.title("Shakal")
        self.geometry("520x720") 
        self.configure(bg="#0A0A0B")
        self.resizable(False, False)
        
        self.input_file = None
        self.output_file = tk.StringVar()

        self._build_ui()

        self.drop_target_register(DND_FILES)
        self.dnd_bind('<<Drop>>', self.handle_drop)
        print("Система готова. Ожидание файла...")

    def _build_ui(self):
        self.logo = ctk.CTkLabel(self, text="SHAKAL", font=("Arial Black", 40), text_color="#FFFFFF")
        self.logo.pack(pady=(35, 0))
        
        self.drop_card = ctk.CTkFrame(self, width=440, height=140, corner_radius=25, 
                                      fg_color="#121214", border_width=1, border_color="#222224")
        self.drop_card.pack(padx=40, pady=(20, 10))
        self.drop_card.pack_propagate(False)

        self.drop_label = ctk.CTkLabel(self.drop_card, text="ПЕРЕТАЩИТЕ ФАЙЛ СЮДА", 
                                       font=("Arial", 14, "bold"), text_color="#555558")
        self.drop_label.place(relx=0.5, rely=0.45, anchor="center")
        
        ctk.CTkButton(self.drop_card, text="выбрать файл вручную", font=("Arial", 11, "underline"),
                      fg_color="transparent", hover=False, text_color="#3B82F6", 
                      command=self.select_file).place(relx=0.5, rely=0.65, anchor="center")

        self.save_card = ctk.CTkFrame(self, fg_color="transparent")
        self.save_card.pack(fill="x", padx=45, pady=10)
        ctk.CTkLabel(self.save_card, text="КУДА СОХРАНИТЬ", font=("Arial", 10, "bold"), text_color="#444446").pack(anchor="w")
        
        row_s = ctk.CTkFrame(self.save_card, fg_color="transparent")
        row_s.pack(fill="x", pady=(5, 0))
        self.entry_save = ctk.CTkEntry(row_s, textvariable=self.output_file, fg_color="#121214", 
                                       border_width=0, height=40, corner_radius=12)
        self.entry_save.pack(side="left", fill="x", expand=True, padx=(0, 10))
        ctk.CTkButton(row_s, text="📁", width=40, height=40, fg_color="#1D1D20", 
                      command=self.select_output_path).pack(side="right")

        self.settings_card = ctk.CTkFrame(self, fg_color="transparent")
        self.settings_card.pack(fill="x", padx=45, pady=10)

        self.quality_var = tk.IntVar(value=80)
        self.ui_quality = self.create_slider(self.settings_card, "СЖАТИЕ", 0, 100, self.quality_var)
        self.pixel_var = tk.IntVar(value=5)
        self.ui_pixel = self.create_slider(self.settings_card, "РАЗМЕР ПИКСЕЛЯ", 1, 50, self.pixel_var)
        self.fps_var = tk.IntVar(value=24)
        self.ui_fps = self.create_slider(self.settings_card, "FPS", 1, 60, self.fps_var)

        self.main_btn = ctk.CTkButton(self, text="УШАТАТЬ В ХЛАМ", height=60, corner_radius=15,
                                      fg_color="#FFFFFF", text_color="#000000", font=("Arial", 16, "bold"),
                                      command=self.start_processing, state="disabled")
        self.main_btn.pack(fill="x", padx=45, pady=(20, 10))

        self.btn_view = ctk.CTkButton(self, text="ПОСМОТРЕТЬ РЕЗУЛЬТАТ", height=45, corner_radius=12,
                                      fg_color="#1D1D20", text_color="#3B82F6", font=("Arial", 13, "bold"),
                                      command=self.open_result, state="disabled")
        self.btn_view.pack(fill="x", padx=45, pady=(0, 10))

        self.progress_bar = ctk.CTkProgressBar(self, height=4, corner_radius=2, fg_color="#121214", progress_color="#3B82F6")
        self.progress_bar.set(0)
        self.progress_bar.pack(fill="x", padx=45, pady=(10, 20))

        self.st_bar = ctk.CTkFrame(self, height=50, corner_radius=0, fg_color="#0D0D0E")
        self.st_bar.pack(side="bottom", fill="x")
        self.st_lbl = ctk.CTkLabel(self.st_bar, text="READY", font=("Arial", 13, "bold"), text_color="#444446")
        self.st_lbl.pack(expand=True)

    def create_slider(self, parent, label_text, f, t, var):
        container = ctk.CTkFrame(parent, fg_color="transparent")
        container.pack(fill="x", pady=6)
        lbl = ctk.CTkLabel(container, text=label_text, font=("Arial", 10, "bold"), text_color=COLOR_INACTIVE)
        lbl.pack(anchor="w")
        row = ctk.CTkFrame(container, fg_color="transparent")
        row.pack(fill="x")
        s = ctk.CTkSlider(row, from_=f, to=t, variable=var, height=16, state="disabled",
                          fg_color=SLIDER_BG_INACTIVE, progress_color=SLIDER_PROGRESS_INACTIVE,
                          button_color=SLIDER_BUTTON_INACTIVE)
        s.pack(side="left", fill="x", expand=True, padx=(0, 10))
        val_lbl = ctk.CTkLabel(row, textvariable=var, font=("Arial", 12, "bold"), width=30, text_color=COLOR_VALUE_INACTIVE)
        val_lbl.pack(side="right")
        return {"slider": s, "label": lbl, "value_label": val_lbl}

    def _set_slider_state(self, ui_dict, active=True):
        state = "normal" if active else "disabled"
        ui_dict["slider"].configure(state=state, fg_color=SLIDER_BG_ACTIVE if active else SLIDER_BG_INACTIVE,
            progress_color=SLIDER_PROGRESS_ACTIVE if active else SLIDER_PROGRESS_INACTIVE,
            button_color=SLIDER_BUTTON_ACTIVE if active else SLIDER_BUTTON_INACTIVE)
        ui_dict["label"].configure(text_color=COLOR_ACTIVE if active else COLOR_INACTIVE)
        ui_dict["value_label"].configure(text_color=COLOR_VALUE_ACTIVE if active else COLOR_VALUE_INACTIVE)

    def handle_drop(self, event):
        path = event.data.strip('{}')
        self.load_file(path)

    def select_file(self):
        path = filedialog.askopenfilename()
        if path: self.load_file(path)

    def select_output_path(self):
        if not self.input_file: return
        ext = os.path.splitext(self.output_file.get())[1]
        path = filedialog.asksaveasfilename(defaultextension=ext, filetypes=[("File", f"*{ext}")])
        if path: self.output_file.set(path)

    def load_file(self, path):
        self.input_file = path
        self.drop_label.configure(text=os.path.basename(path).upper(), text_color="#3B82F6")
        self.main_btn.configure(state="normal")
        ext = path.split('.')[-1].lower()
        is_video = ext in ['mp4', 'avi', 'mov', 'mkv']
        self._set_slider_state(self.ui_quality, True)
        self._set_slider_state(self.ui_pixel, True)
        self._set_slider_state(self.ui_fps, is_video)
        base = os.path.splitext(path)[0]
        self.output_file.set(f"{base}_shakal{'.mp4' if is_video else os.path.splitext(path)[1]}")
        print(f"> Файл загружен: {path}")

    def _shakalize_pil_image(self, img, quality, pixel_size):
        if img.mode != 'RGB': img = img.convert('RGB')
        w, h = img.size
        img = img.resize((max(1, w // pixel_size), max(1, h // pixel_size)), Image.Resampling.BOX)
        if quality > 0:
            img = ImageEnhance.Contrast(img).enhance(1.0 + (quality / 100.0))
            jpeg_q = max(1, int(65 - quality * 0.6))
            for _ in range(int(1 + quality / 20)):
                buf = io.BytesIO()
                img.save(buf, format="JPEG", quality=jpeg_q)
                img = Image.open(buf)
        return img.resize((w, h), Image.Resampling.NEAREST)

    def worker(self):
        try:
            q, p, fps = self.quality_var.get(), self.pixel_var.get(), self.fps_var.get()
            ext = self.input_file.split('.')[-1].lower()
            out_path = self.output_file.get()
            
            print(f"\n--- СТАРТ: {os.path.basename(self.input_file)} ---")
            if ext in ['png', 'jpg', 'jpeg', 'webp']:
                self.progress_bar.configure(mode="indeterminate")
                self.progress_bar.start()
                self._shakalize_pil_image(Image.open(self.input_file), q, p).save(out_path)
            else:
                clip = VideoFileClip(self.input_file)
                total_frames = int(clip.duration * fps)
                processed = 0
                def transform(f):
                    nonlocal processed
                    processed += 1
                    if processed % 10 == 0:
                        self.after(0, lambda: self.progress_bar.set(processed / total_frames))
                    return np.array(self._shakalize_pil_image(Image.fromarray(f), q, p))
                
                shakal = clip.image_transform(transform)
                temp_v = "temp_v.mp4"
                shakal.write_videofile(temp_v, fps=fps, codec="libx264", audio=False, logger='bar')
                
                print("> Обработка звука...")
                ffmpeg_exe = get_ffmpeg_exe()
                ar = [44100, 22050, 11025, 8000][min(3, int(q/30))]
                ab = f"{max(8, 128-q)}k"
                subprocess.run([ffmpeg_exe, "-y", "-i", temp_v, "-i", self.input_file, "-map", "0:v", "-map", "1:a?", 
                                "-c:v", "copy", "-c:a", "aac", "-ar", str(ar), "-b:a", ab, out_path], check=True)
                if os.path.exists(temp_v): os.remove(temp_v)
                clip.close()
            
            print(f" Готово! Сохранено в: {out_path}")
            self.after(0, lambda: self.finish("УСПЕШНО", "success"))
        except Exception as e:
            print(f" ОШИБКА: {e}")
            self.after(0, lambda: self.finish("ОШИБКА", "error"))

    def start_processing(self):
        self.main_btn.configure(state="disabled")
        self.btn_view.configure(state="disabled")
        self.progress_bar.set(0)
        threading.Thread(target=self.worker, daemon=True).start()

    def finish(self, msg, status):
        self.progress_bar.stop()
        self.progress_bar.configure(mode="determinate")
        self.progress_bar.set(1 if status == "success" else 0)
        self.show_status(msg, status)
        self.main_btn.configure(state="normal")
        if status == "success": self.btn_view.configure(state="normal")

    def show_status(self, text, st_type):
        colors = {"success": "#10B981", "error": "#EF4444", "process": "#3B82F6"}
        self.st_bar.configure(fg_color=colors.get(st_type, "#0D0D0E"))
        self.st_lbl.configure(text=text, text_color="#FFFFFF")

    def open_result(self):
        path = self.output_file.get()
        if os.path.exists(path):
            os.startfile(path) if sys.platform == "win32" else subprocess.call(["open", path])

if __name__ == "__main__":
    app = Shakal()
    app.mainloop()
