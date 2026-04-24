import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageEnhance
import io
import os
import sys
import threading
import numpy as np
from moviepy import VideoFileClip
from imageio_ffmpeg import get_ffmpeg_exe
import subprocess

# Класс для перехвата принтов в текстовое поле
class TextRedirector:
    def __init__(self, widget):
        self.widget = widget

    def write(self, str_val):
        self.widget.config(state='normal')
        self.widget.insert('end', str_val)
        self.widget.see('end')
        self.widget.config(state='disabled')

    def flush(self):
        pass

class ShakalizerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Shakal")
        self.root.geometry("480x560")
        self.root.resizable(False, False)

        self.input_file = None
        self.output_file = None 
        self.original_fps = 30
        self.logs_visible = False

        self._build_ui()
        
        # Перенаправляем stdout (принты) в наше окно логов
        sys.stdout = TextRedirector(self.log_text)
        sys.stderr = TextRedirector(self.log_text)

    def _build_ui(self):
        # --- Верхняя часть ---
        self.btn_select = ttk.Button(self.root, text="1. Выбрать исходный файл", command=self.select_file)
        self.btn_select.pack(pady=(10, 0))

        self.lbl_file = ttk.Label(self.root, text="Файл не выбран", foreground="gray")
        self.lbl_file.pack(pady=(0, 5))

        self.btn_save_as = ttk.Button(self.root, text="2. Куда сохранить результат?", command=self.select_output_path, state="disabled")
        self.btn_save_as.pack(pady=(5, 0))

        self.lbl_save = ttk.Label(self.root, text="Путь не выбран", foreground="gray")
        self.lbl_save.pack(pady=(0, 10))

        # Настройки
        settings_frame = ttk.LabelFrame(self.root, text="Настройки деградации")
        settings_frame.pack(pady=5, padx=20, fill="x")

        # 1. Quality
        ttk.Label(settings_frame, text="Уровень шакалов (грязь, JPEG):").pack(anchor="w", padx=5)
        self.quality_var = tk.IntVar(value=80)
        q_frame = ttk.Frame(settings_frame)
        q_frame.pack(fill="x", padx=5, pady=2)
        ttk.Scale(q_frame, from_=0, to=100, variable=self.quality_var, orient="horizontal", 
                  command=lambda s: self.quality_var.set(int(float(s)))).pack(side="left", fill="x", expand=True)
        ttk.Entry(q_frame, textvariable=self.quality_var, width=4).pack(side="right", padx=5)

        # 2. Pixelation
        ttk.Label(settings_frame, text="Размер пикселя (крупность):").pack(anchor="w", padx=5, pady=(5,0))
        self.pixel_var = tk.IntVar(value=5)
        p_frame = ttk.Frame(settings_frame)
        p_frame.pack(fill="x", padx=5, pady=2)
        ttk.Scale(p_frame, from_=1, to=50, variable=self.pixel_var, orient="horizontal",
                  command=lambda s: self.pixel_var.set(int(float(s)))).pack(side="left", fill="x", expand=True)
        ttk.Entry(p_frame, textvariable=self.pixel_var, width=4).pack(side="right", padx=5)

        # 3. FPS
        self.lbl_fps_title = ttk.Label(settings_frame, text="Posterize Time (FPS):")
        self.lbl_fps_title.pack(anchor="w", padx=5, pady=(5,0))
        self.fps_var = tk.IntVar(value=24)
        f_frame = ttk.Frame(settings_frame)
        f_frame.pack(fill="x", padx=5, pady=2)
        ttk.Scale(f_frame, from_=1, to=60, variable=self.fps_var, orient="horizontal",
                  command=lambda s: self.fps_var.set(int(float(s)))).pack(side="left", fill="x", expand=True)
        ttk.Entry(f_frame, textvariable=self.fps_var, width=4).pack(side="right", padx=5)

        # --- Прогресс и Кнопки ---
        self.progress = ttk.Progressbar(self.root, orient="horizontal", length=400, mode="determinate")
        self.progress.pack(pady=10, padx=20, fill="x")

        btn_frame = ttk.Frame(self.root)
        btn_frame.pack(pady=5)

        self.btn_start = ttk.Button(btn_frame, text="УШАТАТЬ В ХЛАМ", command=self.start_processing, state="disabled")
        self.btn_start.pack(side="left", padx=5)

        self.btn_logs = ttk.Button(btn_frame, text="Логи ▼", command=self.toggle_logs)
        self.btn_logs.pack(side="left", padx=5)

        self.lbl_status = ttk.Label(self.root, text="Готов", font=("Arial", 9, "bold"))
        self.lbl_status.pack()

        # --- Скрытая панель логов ---
        self.log_frame = ttk.Frame(self.root)
        self.log_text = tk.Text(self.log_frame, height=10, width=60, state='disabled', font=("Consolas", 8), bg="#f0f0f0")
        self.log_scroll = ttk.Scrollbar(self.log_frame, orient="vertical", command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=self.log_scroll.set)
        
        self.log_text.pack(side="left", fill="both", expand=True)
        self.log_scroll.pack(side="right", fill="y")

    def toggle_logs(self):
        if not self.logs_visible:
            self.log_frame.pack(pady=10, padx=20, fill="both", expand=True)
            self.root.geometry("480x750") # Увеличиваем окно
            self.btn_logs.config(text="Логи ▲")
        else:
            self.log_frame.pack_forget()
            self.root.geometry("480x560") # Возвращаем размер
            self.btn_logs.config(text="Логи ▼")
        self.logs_visible = not self.logs_visible

    def select_file(self):
        filetypes = (("Медиа файлы", "*.png *.jpg *.jpeg *.mp4 *.avi *.mov *.mkv"), ("Все файлы", "*.*"))
        filepath = filedialog.askopenfilename(title="Выбери жертву", filetypes=filetypes)
        if filepath:
            self.input_file = filepath
            ext = filepath.split('.')[-1].lower()
            if ext in ['mp4', 'avi', 'mov', 'mkv']:
                try:
                    clip = VideoFileClip(filepath)
                    self.original_fps = int(clip.fps)
                    clip.close()
                    self.fps_var.set(min(24, self.original_fps))
                except: self.original_fps = 60
            
            self.lbl_file.config(text=os.path.basename(filepath), foreground="black")
            self.btn_save_as.config(state="normal")
            base, ext_orig = os.path.splitext(filepath)
            self.output_file = f"{base}_shakal{'.mp4' if ext in ['mp4', 'avi', 'mov', 'mkv'] else ext_orig}"
            self.lbl_save.config(text=os.path.basename(self.output_file), foreground="black")
            self.btn_start.config(state="normal")
            print(f"[INFO] Выбран файл: {filepath}")

    def select_output_path(self):
        if not self.input_file: return
        path = filedialog.asksaveasfilename(initialfile=os.path.basename(self.output_file))
        if path:
            self.output_file = path
            self.lbl_save.config(text=os.path.basename(path), foreground="black")

    def _shakalize_pil_image(self, img, quality, pixel_size):
        if img.mode != 'RGB': img = img.convert('RGB')
        w, h = img.size
        img = img.resize((max(1, w // pixel_size), max(1, h // pixel_size)), Image.Resampling.BOX)
        if quality > 0:
            img = ImageEnhance.Contrast(img).enhance(1.0 + (quality / 100.0))
            jpeg_q = max(1, int(60 - quality * 0.58))
            for _ in range(int(1 + quality / 20)):
                buf = io.BytesIO()
                img.save(buf, format="JPEG", quality=jpeg_q)
                img = Image.open(buf)
        return img.resize((w, h), Image.Resampling.NEAREST)

    def process_file(self):
        try:
            q, p, fps = self.quality_var.get(), self.pixel_var.get(), self.fps_var.get()
            ext = self.input_file.split('.')[-1].lower()
            
            print(f"[START] Качество: {q}, Пиксель: {p}, FPS: {fps}")
            
            if ext in ['png', 'jpg', 'jpeg']:
                self.progress.config(mode="indeterminate")
                self.progress.start()
                self._shakalize_pil_image(Image.open(self.input_file), q, p).save(self.output_file)
            else:
                self.progress.config(mode="determinate", value=0)
                clip = VideoFileClip(self.input_file)
                total_frames = int(clip.duration * fps)
                
                processed = 0
                def transform_with_progress(f):
                    nonlocal processed
                    processed += 1
                    if processed % 10 == 0:
                        val = (processed / total_frames) * 100
                        self.root.after(0, lambda: self.progress.config(value=val))
                    return np.array(self._shakalize_pil_image(Image.fromarray(f), q, p))

                shakal = clip.image_transform(transform_with_progress)
                temp_v = "temp_v.mp4"
                
                print("[VIDEO] Рендеринг видео потока...")
                shakal.write_videofile(temp_v, fps=fps, codec="libx264", audio=False, logger=None)
                
                print("[AUDIO] Наложение искаженного звука...")
                self._add_bad_audio(temp_v, self.input_file, self.output_file, q)
                
                if os.path.exists(temp_v): os.remove(temp_v)
                clip.close()

            self.root.after(0, self.finish, "Готово!", "green")
        except Exception as e:
            print(f"[ERROR] {e}")
            self.root.after(0, self.finish, "Ошибка!", "red")

    def _add_bad_audio(self, video_v, original_media, output_p, q):
        ffmpeg_exe = get_ffmpeg_exe()
        ar = [44100, 22050, 11025, 8000][min(3, int(q/30))]
        ab = f"{max(8, 128-q)}k"
        cmd = [ffmpeg_exe, "-y", "-i", video_v, "-i", original_media, "-map", "0:v", "-map", "1:a?", "-c:v", "copy", "-c:a", "aac", "-ar", str(ar), "-b:a", ab, output_p]
        subprocess.run(cmd, check=True)

    def start_processing(self):
        self.btn_start.config(state="disabled")
        self.lbl_status.config(text="Шакализация...", foreground="blue")
        threading.Thread(target=self.process_file, daemon=True).start()

    def finish(self, msg, color):
        self.progress.stop()
        self.progress.config(mode="determinate", value=100 if color == "green" else 0)
        self.lbl_status.config(text=msg, foreground=color)
        self.btn_start.config(state="normal")
        messagebox.showinfo("Результат", msg)

if __name__ == "__main__":
    root = tk.Tk()
    app = ShakalizerApp(root)
    root.mainloop()
