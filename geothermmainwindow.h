#ifndef GEOTHERMMAINWINDOW_H
#define GEOTHERMMAINWINDOW_H

#include <QMainWindow>
#include <QAbstractItemModel>
#include "julia.h"

QT_BEGIN_NAMESPACE
namespace Ui { class GeothermMainWindow; }
QT_END_NAMESPACE

class QCSVModel;

class GeothermMainWindow : public QMainWindow
{
    Q_OBJECT

public:
    GeothermMainWindow(QWidget *parent = nullptr);
    ~GeothermMainWindow();
public slots:
    void actionAbout();

private slots:
    void on_pushButton_clicked();

    void on_pushButton_2_clicked();

    void on_calcPushButton_clicked();

    void on_pushButton_3_clicked();

private:
    Ui::GeothermMainWindow *ui;
    QCSVModel * csvModel = nullptr;

protected:
    bool compModuleLoaded = false;
    // QString csvFileName = "";
    QString constructInitialExpr();
public:
    bool checkInitialData();
};

jl_value_t *  handleEval(QString cmd);
bool loadCompModule();

class QCSVModel : public QAbstractItemModel {

private:
    jl_value_t * dataFrame = nullptr;
public:
    QCSVModel(QObject * parent = nullptr) :
        QAbstractItemModel(parent) {}
    int columnCount(const QModelIndex &parent) const override;
    int rowCount (const QModelIndex &parent) const override;
    jl_value_t * setDataFrame(jl_value_t * df);
    QModelIndex index(int row, int column, const QModelIndex &parent = QModelIndex()) const override;
    QModelIndex parent(const QModelIndex &index) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QVariant headerData(int section, Qt::Orientation orientation,
                        int role = Qt::DisplayRole) const override;
    bool isValid() {return dataFrame != nullptr;};
};

#endif // GEOTHERMMAINWINDOW_H
