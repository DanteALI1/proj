// Основная логика анимации замка
document.addEventListener('DOMContentLoaded', function() {
    const lockContainer = document.getElementById('lockContainer');
    const lockFill = document.getElementById('lockFill');
    const lockIcon = document.getElementById('lockIcon');
    const progressText = document.getElementById('progressText');
    const tocSection = document.getElementById('tocSection');
    const pageFooter = document.getElementById('pageFooter');
    
    // Функция для расчета времени анимации в зависимости от устройства
    function getAnimationTimes() {
        if (window.innerWidth <= 480) {
            return { fill: 2000, open: 1000, finish: 1000 };
        } else if (window.innerWidth <= 768) {
            return { fill: 2500, open: 1200, finish: 1000 };
        }
        return { fill: 3000, open: 1500, finish: 1000 };
    }
    
    // Запуск анимации
    setTimeout(startLockAnimation, 300);
    
    function startLockAnimation() {
        const times = getAnimationTimes();
        
        // Этап 1: Заполнение замка
        lockFill.style.clipPath = 'polygon(0% 0%, 100% 0%, 100% 100%, 0% 100%)';
        progressText.textContent = "Проверка целостности системы...";
        
        // Этап 2: Открытие замка
        setTimeout(() => {
            lockIcon.classList.remove('fa-lock');
            lockIcon.classList.add('fa-lock-open');
            lockIcon.style.transform = 'translate(-50%, -50%) rotate(10deg)';
            progressText.textContent = "Открытие доступа к системе безопасности...";
            
            // Этап 3: Завершение анимации
            setTimeout(() => {
                lockContainer.style.opacity = '0';
                lockContainer.style.transform = 'scale(1.2)';
                
                setTimeout(() => {
                    lockContainer.style.display = 'none';
                    tocSection.style.opacity = '1';
                    tocSection.style.transform = 'translateY(0)';
                    pageFooter.style.opacity = '1';
                    
                    // Плавная прокрутка к началу контента
                    setTimeout(() => {
                        tocSection.scrollIntoView({ 
                            behavior: 'smooth', 
                            block: 'start'
                        });
                    }, 300);
                }, 1000);
            }, times.finish);
        }, times.fill);
    }
    
    // Обработчик изменения ориентации экрана
    window.addEventListener('orientationchange', function() {
        // При смене ориентации перезапускаем анимацию
        if (lockContainer.style.display !== 'none') {
            lockContainer.style.display = 'flex';
            lockFill.style.clipPath = 'polygon(50% 50%, 50% 50%, 50% 50%, 50% 50%)';
            lockIcon.classList.remove('fa-lock-open');
            lockIcon.classList.add('fa-lock');
            lockIcon.style.transform = 'translate(-50%, -50%)';
            progressText.textContent = "Загрузка системы безопасности...";
            
            setTimeout(startLockAnimation, 500);
        }
    });
});